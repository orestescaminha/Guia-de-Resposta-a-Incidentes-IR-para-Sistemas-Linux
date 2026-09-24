#!/usr/bin/env python3
import os
import glob
import hashlib
import json
import sys
from datetime import datetime

# Locais de persistência mapeados (arquivos e wildcards)
PERSISTENCE_TARGETS = [
    # 1. Cron jobs
    "/etc/crontab",
    "/etc/cron.*/*",
    "/var/spool/cron/crontabs/*",
    # 2. Chaves e config SSH
    "/root/.ssh/authorized_keys",
    "/home/*/.ssh/authorized_keys",
    "/etc/ssh/sshd_config",
    "/etc/ssh/sshd_config.d/*",
    # 3. Unidades Systemd
    "/etc/systemd/system/*",
    "/lib/systemd/system/*",
    "/root/.config/systemd/user/*",
    "/home/*/.config/systemd/user/*",
    # 4. Perfis de Shell
    "/etc/profile",
    "/etc/profile.d/*",
    "/etc/bash.bashrc",
    "/root/.bashrc",
    "/root/.bash_profile",
    "/home/*/.bashrc",
    "/home/*/.bash_profile",
    # 5. Inicialização Legada
    "/etc/rc.local",
    "/etc/init.d/*",
    "/etc/rc*.d/*",
    # 6. Preload de Bibliotecas e Módulos Kernel
    "/etc/ld.so.preload",
    "/etc/modules-load.d/*"
]

BASELINE_FILE = "/var/log/persistencia_baseline.json"

def compute_sha256(filepath):
    """Calcula o hash SHA-256 de um arquivo em blocos."""
    hasher = hashlib.sha256()
    try:
        with open(filepath, 'rb') as f:
            while chunk := f.read(65536):
                hasher.update(chunk)
        return hasher.hexdigest()
    except (PermissionError, FileNotFoundError, IsADirectoryError):
        return None

def collect_current_state():
    """Varre todos os caminhos definidos e gera o mapa caminho -> hash."""
    current_state = {}
    for target in PERSISTENCE_TARGETS:
        # Expande wildcards como /etc/cron.*/* ou /home/*/.bashrc
        matched_paths = glob.glob(target)
        for path in matched_paths:
            if os.path.isfile(path) and not os.path.islink(path):
                file_hash = compute_sha256(path)
                if file_hash:
                    current_state[path] = file_hash
    return current_state

def create_baseline():
    """Gera o arquivo inicial de baseline."""
    state = collect_current_state()
    with open(BASELINE_FILE, 'w') as f:
        json.dump(state, f, indent=4)
    print(f"[+] Baseline criada com sucesso em '{BASELINE_FILE}'. Total de arquivos monitorados: {len(state)}")

def audit_changes():
    """Compara o estado atual com a baseline salva."""
    if not os.path.exists(BASELINE_FILE):
        print(f"[-] Arquivo de baseline '{BASELINE_FILE}' não encontrado. Execute com '--init' primeiro.")
        sys.exit(1)

    with open(BASELINE_FILE, 'r') as f:
        baseline = json.load(f)

    current = collect_current_state()
    
    baseline_files = set(baseline.keys())
    current_files = set(current.keys())

    # Identifica diferenças
    added = current_files - baseline_files
    removed = baseline_files - current_files
    common = baseline_files & current_files

    modified = [f for f in common if baseline[f] != current[f]]

    # Exibe relatório de alertas
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n==========================================")
    print(f"   RELATÓRIO DE INTEGRIDADE ({timestamp})")
    print(f"==========================================")

    if not added and not removed and not modified:
        print("[OK] Nenhuma alteração detectada nos locais de persistência.")
        return

    if added:
        print("\n[ALERTA - ARQUIVOS NOVOS DETECTADOS]")
        for f in added:
            print(f"  + {f} (Hash: {current[f]})")

    if modified:
        print("\n[ALERTA - ARQUIVOS MODIFICADOS]")
        for f in modified:
            print(f"  * {f}")
            print(f"    - Hash Antigo: {baseline[f]}")
            print(f"    + Hash Novo:   {current[f]}")

    if removed:
        print("\n[ALERTA - ARQUIVOS REMOVIDOS]")
        for f in removed:
            print(f"  - {f}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--init":
        create_baseline()
    else:
        audit_changes()

