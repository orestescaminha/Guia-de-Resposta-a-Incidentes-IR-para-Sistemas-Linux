#!/usr/bin/env bash
# Script de Análise Rápida e Correlação de Autenticação
set -euo pipefail

LOG_AUTH="/var/log/auth.log"
[ ! -f "$LOG_AUTH" ] && LOG_AUTH="/var/log/secure"

echo "=========================================="
echo " 1. RESUMO DE TENTATIVAS SSH / AUTENTICAÇÃO"
echo "=========================================="
# Busca em logs normais e compactados (.gz)
zgrep -Ei 'accepted|failed|invalid user|Accepted publickey' $LOG_AUTH* 2>/dev/null | tail -n 30 || true

echo -e "\n=========================================="
echo " 2. ESCALONAMENTO DE PRIVILÉGIOS (SUDO & SU)"
echo "=========================================="
zgrep -Ei 'sudo:.*COMMAND=|su:session opened' $LOG_AUTH* 2>/dev/null | tail -n 20 || true

echo -e "\n=========================================="
echo " 3. VERIFICAÇÃO DE INTEGRIDADE DOS LOGS BINÁRIOS"
echo "=========================================="
for binlog in /var/log/wtmp /var/log/btmp; do
    if [ -f "$binlog" ]; then
        size=$(stat -c%s "$binlog")
        if [ "$size" -eq 0 ]; then
            echo "[ALERTA CRÍTICO] O arquivo $binlog está com TAMANHO ZERO (possível remoção de rastros/tampering)!"
        else
            echo "[OK] $binlog intacto (Tamanho: $size bytes)."
        fi
    fi
done

echo -e "\n=========================================="
echo " 4. ÚLTIMOS LOGINS E FALHAS REGISTRADAS"
echo "=========================================="
echo "--- Sucessos (last) ---"
last -Faixw | head -n 10
echo "--- Falhas (lastb) ---"
lastb -Fa | head -n 10
