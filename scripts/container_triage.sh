#!/usr/bin/env bash
# Script de Triagem Forense em Containers (Host-Level)
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Uso: $0 <PID_SUSPEITO>"
    exit 1
fi

TARGET_PID=$1
OUTPUT_DIR="/tmp/container_triage_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " 1. MAPEAMENTO DE CGROUP E NAMESPACE"
echo "=================================================="
# Extrai o Container ID completo a partir do cgroup do processo
CONTAINER_ID=$(cat /proc/"$TARGET_PID"/cgroup | grep -oE '[0-9a-f]{64}' | head -n 1 || true)

if [ -z "$CONTAINER_ID" ]; then
    echo "[!] Container ID não encontrado. O processo pode não estar isolado ou já foi encerrado."
    exit 1
fi

echo "[+] PID $TARGET_PID mapeado para o Container ID: ${CONTAINER_ID:0:12}..."
cp /proc/"$TARGET_PID"/cgroup "$OUTPUT_DIR/cgroup.txt"

echo -e "\n=================================================="
echo " 2. IDENTIFICAÇÃO DE RUNTIME E PAUSA DO CONTAINER"
echo "=================================================="
RUNTIME=""
if command -v docker &>/dev/null && docker ps -q --no-trunc | grep -q "$CONTAINER_ID"; then
    RUNTIME="docker"
    echo "[+] Runtime Docker detectado. Pausando container..."
    docker pause "$CONTAINER_ID"
elif command -v crictl &>/dev/null && crictl ps -q --no-trunc | grep -q "$CONTAINER_ID"; then
    RUNTIME="crictl"
    echo "[+] Runtime containerd/CRI-O detectado. Identificando pod associado..."
    crictl inspect "$CONTAINER_ID" > "$OUTPUT_DIR/crictl_inspect.json"
else
    echo "[!] Runtime não identificado ou container indisponível. Prosseguindo com extração em disco."
fi

echo -e "\n=================================================="
echo " 3. CAPTURA DA CAMADA GRAVÁVEL (WRITABLE LAYER)"
echo "=================================================="
if [ "$RUNTIME" == "docker" ]; then
    echo "[+] Exportando diff e commit via Docker..."
    docker diff "$CONTAINER_ID" > "$OUTPUT_DIR/docker_diff.txt"
    docker commit "$CONTAINER_ID" "evidence_${CONTAINER_ID:0:12}"
    docker save "evidence_${CONTAINER_ID:0:12}" -o "$OUTPUT_DIR/evidence_image.tar"
else
    # Extração forense direta do OverlayFS (padrão containerd)
    echo "[+] Buscando camada gravável no OverlayFS do Host..."
    LOWER_UPPER=$(grep overlay /proc/"$TARGET_PID"/mountinfo | grep -oE 'upperdir=[^,]+') || true
    
    if [ -n "$LOWER_UPPER" ]; then
        UPPER_DIR=$(echo "$LOWER_UPPER" | cut -d'=' -f2)
        echo "[+] Diretório da camada superior (Upperdir): $UPPER_DIR"
        
        # Cria um arquivo tar comprimido da camada gravável com preservação rigorosa (MACB)
        tar -czf "$OUTPUT_DIR/upperdir_snapshot.tar.gz" --sparse --acls --xattrs --numeric-owner -C "$UPPER_DIR" .
        echo "[+] Camada gravável copiada com sucesso."
    else
        echo "[-] Não foi possível isolar o upperdir do OverlayFS."
    fi
fi

echo -e "\n=================================================="
echo " 4. COLETA DE CONEXÕES DA NAMESPACE DE REDE (NSENTER)"
echo "=================================================="
echo "[+] Coletando sockets de rede diretamente na namespace do container..."
nsenter -t "$TARGET_PID" -n ss -antpu > "$OUTPUT_DIR/container_network_sockets.txt" 2>/dev/null || true

echo -e "\n[+] Triagem concluída. Evidências salvas em: $OUTPUT_DIR"
