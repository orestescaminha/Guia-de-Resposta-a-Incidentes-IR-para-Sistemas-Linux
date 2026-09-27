#!/usr/bin/env bash
# Script de Aquisição de Memória RAM e Análise Offline via Volatility 3
set -euo pipefail

export TZ="UTC"

MODE="${1:-local}" # Opções: 'local' ou 'network'
OUTPUT_DIR="/mnt/evidence/ram_acquisition_$(date -u +%Y%m%dT%H%M%SZ)"
MEM_FILE="${OUTPUT_DIR}/mem.lime"
HASH_FILE="${MEM_FILE}.sha256"

mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " 1. AQUISIÇÃO DE MEMÓRIA RAM (MODO: ${MODE^^})"
echo "=================================================="

if [ "$MODE" == "local" ]; then
    if [ -f "./avml" ]; then
        echo "[+] Executando AVML para aquisição local de memória..."
        ./avml "$MEM_FILE"
        echo "[+] Aquisição concluída. Memória salva em: $MEM_FILE"
    else
        echo "[!] Erro: Executável './avml' não foi encontrado no diretório atual."
        exit 1
    fi

elif [ "$MODE" == "network" ]; then
    if [ -f "./lime.ko" ]; then
        echo "[+] Carregando módulo LiME para transmissão via rede na porta TCP 4444..."
        echo "[!] CERTIFIQUE-SE DE QUE O RECEPTOR (ex: nc <IP> 4444 > mem.lime) ESTÁ ATIVO."
        insmod ./lime.ko 'path="tcp:4444" format=lime'
        echo "[+] Módulo LiME descarregado/concluído."
    else
        echo "[!] Erro: Módulo 'lime.ko' não encontrado."
        exit 1
    fi
else
    echo "[!] Modo inválido. Use '$0 local' ou '$0 network'."
    exit 1
fi

# -----------------------------------------------------------------
# 2. CALCULO E VALIDAÇÃO DA CADEIA DE CUSTÓDIA (HASH SHA-256)
# -----------------------------------------------------------------
if [ -f "$MEM_FILE" ]; then
    echo -e "\n=================================================="
    echo " 2. GERANDO HASH DE INTEGRIDADE (SHA-256)"
    echo "=================================================="
    sha256sum "$MEM_FILE" | tee "$HASH_FILE"
    
    # Define arquivo de memória como somente leitura para evitar alteração acidental
    chmod 440 "$MEM_FILE"
    echo "[+] Arquivo de imagem bloqueado para gravação (chmod 440)."
fi

# -----------------------------------------------------------------
# 3. ANÁLISE AUTOMATIZADA COM VOLATILITY 3
# -----------------------------------------------------------------
echo -e "\n=================================================="
echo " 3. EXECUÇÃO DE PLUGINS DO VOLATILITY 3"
echo "=================================================="

if command -v vol3 &>/dev/null && [ -f "$MEM_FILE" ]; then
    PLUGINS=("linux.pslist" "linux.bash" "linux.malfind")
    
    for plugin in "${PLUGINS[@]}"; do
        echo "[+] Executando plugin: $plugin..."
        vol3 -f "$MEM_FILE" "$plugin" > "${OUTPUT_DIR}/${plugin}.txt" 2>&1 || true
        echo "    -> Resultado salvo em: ${OUTPUT_DIR}/${plugin}.txt"
    done
else
    echo "[!] Volatility 3 (vol3) não instalado ou imagem de memória indisponível. Etapa de análise ignorada."
fi

echo -e "\n=================================================="
echo " Processo concluído com sucesso. Artefatos em: $OUTPUT_DIR"
echo "=================================================="
