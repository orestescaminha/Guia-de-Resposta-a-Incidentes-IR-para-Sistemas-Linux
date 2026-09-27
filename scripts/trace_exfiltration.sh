#!/usr/bin/env bash
# Script de Triagem para Rastreamento de Preparação (Staging) e Exfiltração
set -euo pipefail

# Define fuso horário UTC para consistência forense
export TZ="UTC"

START_TIME="${1:-2026-09-01}" # Padrão: início do incidente (passe como parâmetro: AAAA-MM-DD)
OUTPUT_DIR="/tmp/exfiltration_audit_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " 1. VARREDURA DE DIRETÓRIOS DE STAGING E ARQUIVOS RECENTES"
echo "=================================================="
STAGING_DIRS="/tmp /dev/shm /var/tmp /dev/mqueue /run/user/*"

# Identifica arquivos modificados após o início do incidente e que sejam arquivos compactados/grandes
find $STAGING_DIRS -type f -newerct "$START_TIME" 2>/dev/null | while read -r filepath; do
    file_info=$(file "$filepath" 2>/dev/null || true)
    # Filtra por extensões ou assinaturas típicas de archives/empacotamento
    if echo "$file_info" | grep -Ei 'archive|compressed|ZIP|Tar|7-zip|RAR|GZ' >/dev/null; then
        echo "[ALERTA - ARQUIVO COMPACTADO SUSPEITO] $filepath"
        stat -c "  Tamanho: %s bytes | Criado/Modificado: %y" "$filepath"
    fi
done | tee "$OUTPUT_DIR/suspicious_staging_files.txt"

echo -e "\n=================================================="
echo " 2. COMANDOS DE TRANSFERÊNCIA E EXFILTRAÇÃO NO HISTÓRICO"
echo "=================================================="
TRANSFER_PATTERN='tar |zip |7z |rar |rclone|curl|wget|scp |rsync |nc |ncat |socat |aws s3|python.*http|mega'

find /home /root -maxdepth 3 \( -name "*_history" -o -name ".zsh_history" \) -type f 2>/dev/null | while read -r hist_file; do
    matches=$(grep -Ein "$TRANSFER_PATTERN" "$hist_file" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        echo "[!] Utilidade de exfiltração encontrada em: $hist_file"
        echo "$matches" | sed 's/^/    /'
    fi
done | tee "$OUTPUT_DIR/history_exfiltration_commands.txt"

echo -e "\n=================================================="
echo " 3. CONSULTA DE EVENTOS DE ACESSO A ARQUIVOS (AUDITD)"
echo "=================================================="
if command -v ausearch &>/dev/null; then
    echo "[+] Consultando logs do Auditd por acesso a arquivos..."
    ausearch -k file_access -ts "$START_TIME" --raw 2>/dev/null | aureport -f -i > "$OUTPUT_DIR/auditd_file_report.txt" || true
    echo "[+] Relatório do auditd salvo em: $OUTPUT_DIR/auditd_file_report.txt"
else
    echo "[!] Auditd não instalado ou inativo no sistema."
fi

echo -e "\n=================================================="
echo " 4. SOCKETS DE REDE COM ALTO VOLUME DE DADOS TRANSMITIDOS"
echo "=================================================="
# Exibe sockets TCP estabelecidos e estatísticas de bytes enviados/recebidos
echo "[+] Conexões TCP ativas e métricas de tráfego:"
ss -tin state established 2>/dev/null | grep -E -B1 'bytes_sent|send' | head -n 30 | tee "$OUTPUT_DIR/network_traffic_stats.txt"

echo -e "\n=================================================="
echo " Relatório concluído. Evidências salvas em: $OUTPUT_DIR"
echo "=================================================="
