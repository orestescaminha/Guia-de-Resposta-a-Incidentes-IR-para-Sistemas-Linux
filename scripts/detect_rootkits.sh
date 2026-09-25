#!/usr/bin/env bash
# Script de Detecção de Rootkits e Ocultação por Discordância (Cross-View Analysis)
set -euo pipefail

echo "=================================================="
echo " 1. DISCORDÂNCIA DE PROCESSOS (/proc vs ps)"
echo "=================================================="
# Extrai PIDs do /proc e do ps
proc_pids=$(ls /proc | grep -E '^[0-9]+$' | sort -n -u)
ps_pids=$(ps -ef | awk '{print $2}' | grep -E '^[0-9]+$' | sort -n -u)

# PIDs presentes em /proc mas ausentes na saída do ps
hidden_pids=$(comm -23 <(echo "$proc_pids") <(echo "$ps_pids"))

if [ -n "$hidden_pids" ]; then
    echo "[ALERTA CRÍTICO] Processos OCULTOS detectados (visíveis em /proc, mas invisíveis no 'ps')!"
    for pid in $hidden_pids; do
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "Desconhecido/Excluído")
        echo "  -> PID Oculto: $pid | Linha de comando: $cmdline"
    done
else
    echo "[OK] Nenhuma discordância de PIDs encontrada entre /proc e ps."
fi

echo -e "\n=================================================="
echo " 2. INTEGRIDADE DOS BINÁRIOS DO SISTEMA"
echo "=================================================="
if command -v rpm &>/dev/null; then
    echo "[+] Verificando pacotes via RPM..."
    rpm -Va 2>/dev/null | grep '^..5' || echo "[OK] Nenhum binário alterado via RPM."
elif command -v debsums &>/dev/null; then
    echo "[+] Verificando pacotes via debsums..."
    debsums -c 2>/dev/null | head -n 30 || echo "[OK] Nenhum binário alterado via debsums."
else
    echo "[!] Nem RPM nem debsums encontrados no sistema."
fi

echo -e "\n=================================================="
echo " 3. DISCORDÂNCIA DE MÓDULOS DO KERNEL (/proc/modules vs /sys/module)"
echo "=================================================="
if [ -d "/sys/module" ]; then
    proc_mods=$(awk '{print $1}' /proc/modules | tr '-' '_' | sort -u)
    sys_mods=$(ls /sys/module | tr '-' '_' | sort -u)

    # Identifica diretórios em /sys/module que não constam em /proc/modules
    hidden_mods=$(comm -23 <(echo "$sys_mods") <(echo "$proc_mods") | grep -Ev '^(module|ksettings|vt)$' || true)

    if [ -n "$hidden_mods" ]; then
        echo "[ALERTA CRÍTICO] Módulos de Kernel OCULTOS detectados em /sys/module!"
        echo "$hidden_mods"
    else
        echo "[OK] Nenhuma inconsistência encontrada entre /proc/modules e /sys/module."
    fi
fi

echo -e "\n=================================================="
echo " 4. VERIFICAÇÃO DE ARTEFATOS E PROGRAMAS eBPF"
echo "=================================================="
if command -v bpftool &>/dev/null; then
    echo "[+] Programas eBPF carregados no kernel:"
    bpftool prog list 2>/dev/null | head -n 20 || echo "Nenhum programa eBPF listado."
    
    echo -e "\n[+] Links eBPF ativos (Kprobes / Tracepoints):"
    bpftool link list 2>/dev/null || true
else
    echo "[!] 'bpftool' não instalado. Não foi possível auditar os objetos eBPF do kernel."
fi

echo -e "\n[+] Objetos ancorados no sistema de arquivos BPF (/sys/fs/bpf):"
ls -la /sys/fs/bpf 2>/dev/null || echo "Nenhum objeto encontrado em /sys/fs/bpf."
