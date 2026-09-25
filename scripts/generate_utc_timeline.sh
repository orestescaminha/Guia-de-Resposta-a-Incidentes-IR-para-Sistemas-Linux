#!/usr/bin/env bash
# Script de Construção e Normalização de Linhas do Tempo Forenses (UTC)
set -euo pipefail

# Força a execução de todos os comandos e ferramentas em UTC
export TZ="UTC"

CASE_DIR="./timeline_analysis_$(date -u +%Y%m%dT%H%M%SZ)"
IMAGE_PATH="${1:-}" # Passar o caminho da imagem de disco (.dd/.raw) como argumento se disponível
START_DATE="2026-09-01"

mkdir -p "$CASE_DIR"

echo "=================================================="
echo " 1. COLETANDO ATIVIDADE RECENTE DO FS (SISTEMA AO VIVO)"
echo "=================================================="
# Coleta arquivos modificados/alterados a partir da data de corte e formata em UTC
find / -xdev -newerct "$START_DATE" -printf '%TY-%Tm-%Td %TT %p\n' 2>/dev/null | sort -n > "$CASE_DIR/live_filesystem_ctime.txt"
echo "[+] Arquivos do sistema ao vivo alterados após $START_DATE salvos em: $CASE_DIR/live_filesystem_ctime.txt"

echo -e "\n=================================================="
echo " 2. EXTRAÇÃO DE BODYFILE & MACTIME (SLEUTH KIT)"
echo "=================================================="
if [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ]; then
    echo "[+] Processando imagem de disco: $IMAGE_PATH"
    
    # Gerando o bodyfile do Sleuth Kit
    fls -r -m / "$IMAGE_PATH" > "$CASE_DIR/body.txt" 2>/dev/null || true
    
    # Processando o bodyfile em formato UTC do dia inicial informado até o presente
    mactime -b "$CASE_DIR/body.txt" -d -z UTC "$START_DATE".. > "$CASE_DIR/mactime_timeline.csv"
    echo "[+] Timeline mactime (UTC) gerada em: $CASE_DIR/mactime_timeline.csv"
else
    echo "[!] Nenhuma imagem de disco informada. Pulando etapa de fls/mactime."
    echo "    Sintaxe de uso com imagem: $0 /caminho/para/imagem.dd"
fi

echo -e "\n=================================================="
echo " 3. SUPER TIMELINE VIA PLASO / LOG2TIMELINE"
echo "=================================================="
if [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ] && command -v log2timeline &>/dev/null; then
    PLASO_STORAGE="$CASE_DIR/case.plaso"
    
    echo "[+] Executando log2timeline (Plaso)..."
    log2timeline --status_view linear "$PLASO_STORAGE" "$IMAGE_PATH"
    
    echo "[+] Exportando Super Timeline ordenada em formato CSV (UTC)..."
    psort -o l2tcsv -w "$CASE_DIR/super_timeline.csv" "$PLASO_STORAGE" "date > '$START_DATE 00:00:00'"
    echo "[+] Super Timeline salva em: $CASE_DIR/super_timeline.csv"
else
    echo "[!] Plaso/log2timeline não instalado ou imagem não fornecida. Etapa da Super Timeline pulada."
fi

echo -e "\n=================================================="
echo " 4. MÚLTIPLOS TIMESTAMPS (STAT FORMATADO)"
echo "=================================================="
echo "Para verificar os 4 timestamps (MACB) de um arquivo específico em UTC, utilize:"
echo "  TZ=UTC stat -c 'Arquivo: %n | Acesso (A): %x | Modificação (M): %y | Alteração (C): %z | Criação (B): %w' <arquivo>"
