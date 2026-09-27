#!/usr/bin/env bash
# Script Forense Automatizado de Análise de Processos via /proc
set -euo pipefail

# Garante saída em formato UTC
export TZ="UTC"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUTPUT_DIR="/tmp/proc_investigation_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " 1. BUSCANDO PROCESSOS COM EXECUTÁVEIS DELETADOS"
echo "=================================================="

# Localiza todos os PIDs com links de 'exe' contendo '(deleted)'
DELETED_PIDS=$(ls -la /proc/*/exe 2>/dev/null | grep '(deleted)' | awk '{print $9}' | cut -d'/' -f3 | sort -u || true)

if [ -z "$DELETED_PIDS" ]; then
    echo "[OK] Nenhum processo rodando a partir de binário excluído foi encontrado."
    exit 0
fi

echo "[ALERTA CRÍTICO] Processos suspeitos detectados rodando de arquivos deletados!"
echo "PIDs afetados: $(echo $DELETED_PIDS | tr '\n' ' ')"

for PID in $DELETED_PIDS; do
    # Verifica se o processo ainda existe na tabela do kernel
    if [ ! -d "/proc/$PID" ]; then
        continue
    fi

    PID_DIR="${OUTPUT_DIR}/PID_${PID}"
    mkdir -p "$PID_DIR"

    echo -e "\n--------------------------------------------------"
    echo " [+] Processando PID: $PID"
    echo "--------------------------------------------------"

    # 1. Recupera a linha de comando (cmdline)
    if [ -f "/proc/$PID/cmdline" ]; then
        tr '\0' ' ' < "/proc/$PID/cmdline" > "$PID_DIR/cmdline.txt"
        echo "" >> "$PID_DIR/cmdline.txt"
        echo "  [+] Linha de comando salva em: cmdline.txt"
    fi

    # 2. Captura o diretório de trabalho atual (cwd)
    ls -la "/proc/$PID/cwd" > "$PID_DIR/cwd.txt" 2>/dev/null || true
    echo "  [+] Diretorio de trabalho salvo em: cwd.txt"

    # 3. Lista os descritores de arquivos abertos e sockets (fd)
    ls -la "/proc/$PID/fd" > "$PID_DIR/fd_list.txt" 2>/dev/null || true
    echo "  [+] Descritores de arquivos salvos em: fd_list.txt"

    # 4. Extrai variáveis de ambiente (environ)
    if [ -f "/proc/$PID/environ" ]; then
        tr '\0' '\n' < "/proc/$PID/environ" > "$PID_DIR/environ.txt" 2>/dev/null || true
        echo "  [+] Variaveis de ambiente salvas em: environ.txt"
    fi

    # 5. Captura os mapas de memória (maps)
    if [ -f "/proc/$PID/maps" ]; then
        cat "/proc/$PID/maps" > "$PID_DIR/memory_maps.txt" 2>/dev/null || true
        echo "  [+] Mapa de memoria salvo em: memory_maps.txt"
    fi

    # 6. Recupera o binario executavel deletado e calcula o hash
    RECOVERED_BIN="${PID_DIR}/recovered_binary_${PID}.bin"
    if cp "/proc/$PID/exe" "$RECOVERED_BIN" 2>/dev/null; then
        echo "  [+] Executavel recuperado em: $(basename $RECOVERED_BIN)"
        sha256sum "$RECOVERED_BIN" > "${RECOVERED_BIN}.sha256"
        chmod 440 "$RECOVERED_BIN"
        echo "  [+] Hash SHA-256 calculado e arquivo protegido contra alteracao."
    else
        echo "  [-] Falha ao copiar o binario de /proc/$PID/exe."
    fi
done

echo -e "\n=================================================="
echo " Investigacao concluida. Todos os artefatos estao em:"
echo " $OUTPUT_DIR"
echo "=================================================="
