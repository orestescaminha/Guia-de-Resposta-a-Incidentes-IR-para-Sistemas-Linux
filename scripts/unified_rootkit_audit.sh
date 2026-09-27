#!/usr/bin/env bash
# Script de Auditoria e Detecção Unificada de Rootkits
set -euo pipefail

# Garante a execução em UTC para consistência de logs
export TZ="UTC"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
REPORT_DIR="/var/log/rootkit_audit_${TIMESTAMP}"
SUMMARY_FILE="${REPORT_DIR}/UNIFIED_SUMMARY.txt"

mkdir -p "$REPORT_DIR"

echo "==================================================" | tee -a "$SUMMARY_FILE"
echo " RELATÓRIO UNIFICADO DE VERIFICAÇÃO DE ROOTKITS " | tee -a "$SUMMARY_FILE"
echo " Data/Hora (UTC): ${TIMESTAMP}"                   | tee -a "$SUMMARY_FILE"
echo " Host: $(hostname)"                                | tee -a "$SUMMARY_FILE"
echo "==================================================" | tee -a "$SUMMARY_FILE"

# -----------------------------------------------------------------
# 1. EXECUÇÃO DO CHKROOTKIT
# -----------------------------------------------------------------
echo -e "\n[+] 1. Executando chkrootkit..." | tee -a "$SUMMARY_FILE"
CHK_LOG="${REPORT_DIR}/chkrootkit.log"

if command -v chkrootkit &>/dev/null; then
    # -q exibe apenas alertas/infrações
    chkrootkit -q > "$CHK_LOG" 2>&1 || true
    
    # Filtra alertas relevantes (ignora falsos positivos comuns de pacotes/sufixos)
    INFECTED_CHK=$(grep -Ei 'INFECTED|PACKET SNIFFER' "$CHK_LOG" | grep -v 'NOT INFECTED' || true)
    
    if [ -n "$INFECTED_CHK" ]; then
        echo "  [ALERTA - CHKROOTKIT DETECTOU ANOMALIAS]" | tee -a "$SUMMARY_FILE"
        echo "$INFECTED_CHK" | sed 's/^/    /' | tee -a "$SUMMARY_FILE"
    else
        echo "  [OK] Nenhuma infecção evidente detectada pelo chkrootkit." | tee -a "$SUMMARY_FILE"
    fi
else
    echo "  [!] chkrootkit não está instalado no sistema." | tee -a "$SUMMARY_FILE"
fi

# -----------------------------------------------------------------
# 2. EXECUÇÃO DO RKHUNTER
# -----------------------------------------------------------------
echo -e "\n[+] 2. Executando rkhunter..." | tee -a "$SUMMARY_FILE"
RKH_LOG="${REPORT_DIR}/rkhunter.log"

if command -v rkhunter &>/dev/null; then
    # --sk: skip-keypress | --rwo: report-warnings-only
    rkhunter --check --sk --rwo --logfile "$RKH_LOG" > /dev/null 2>&1 || true
    
    if [ -s "$RKH_LOG" ]; then
        echo "  [ALERTA - RKHUNTER DETECTOU AVISOS]" | tee -a "$SUMMARY_FILE"
        cat "$RKH_LOG" | sed 's/^/    /' | tee -a "$SUMMARY_FILE"
    else
        echo "  [OK] NENHUM aviso gerado pelo rkhunter." | tee -a "$SUMMARY_FILE"
    fi
else
    echo "  [!] rkhunter não está instalado no sistema." | tee -a "$SUMMARY_FILE"
fi

# -----------------------------------------------------------------
# 3. VERIFICAÇÃO POR DISCORDÂNCIA (CROSS-VIEW DO KERNEL / PROC)
# -----------------------------------------------------------------
echo -e "\n[+] 3. Executando verificação de discordância (/proc vs ps)..." | tee -a "$SUMMARY_FILE"

proc_pids=$(ls /proc | grep -E '^[0-9]+$' | sort -n -u)
ps_pids=$(ps -ef | awk '{print $2}' | grep -E '^[0-9]+$' | sort -n -u)
hidden_pids=$(comm -23 <(echo "$proc_pids") <(echo "$ps_pids"))

if [ -n "$hidden_pids" ]; then
    echo "  [ALERTA CRÍTICO - PROCESSOS OCULTOS ENCONTRADOS]" | tee -a "$SUMMARY_FILE"
    for pid in $hidden_pids; do
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "Desconhecido/Excluído")
        echo "    PID Oculto: $pid | Comando: $cmdline" | tee -a "$SUMMARY_FILE"
    done
else
    echo "  [OK] Nenhuma discordância entre /proc e ps." | tee -a "$SUMMARY_FILE"
fi

echo -e "\n==================================================" | tee -a "$SUMMARY_FILE"
echo " Relatório consolidado salvo em: $SUMMARY_FILE"             | tee -a "$SUMMARY_FILE"
echo " Logs brutos disponíveis no diretório: $REPORT_DIR"         | tee -a "$SUMMARY_FILE"
echo "==================================================" | tee -a "$SUMMARY_FILE"
