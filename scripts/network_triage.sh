#!/usr/bin/env bash
# Script Automatizado de Triagem e Investigação de Rede ao Vivo no Linux
set -euo pipefail

# Define fuso horário UTC para padronização forense
export TZ="UTC"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUTPUT_DIR="/tmp/network_triage_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " 1. COLETANDO SOCKETS DE REDE (ss & lsof)"
echo "=================================================="

# 1.1 Coleta via ss
ss -antpu > "$OUTPUT_DIR/ss_sockets.txt" 2>/dev/null || true
echo "[+] Conexoes ativas e portas em escuta salvas via 'ss'."

# 1.2 Coleta via lsof
lsof -i -n -P > "$OUTPUT_DIR/lsof_sockets.txt" 2>/dev/null || true
echo "[+] Descritores de arquivos de rede salvos via 'lsof'."

echo -e "\n=================================================="
echo " 2. LEITURA E DECODIFICAÇÃO DA VERDADE DO KERNEL (/proc/net)"
echo "=================================================="

# Copia as tabelas brutas do kernel
cp /proc/net/tcp "$OUTPUT_DIR/proc_net_tcp_raw.txt" 2>/dev/null || true
cp /proc/net/tcp6 "$OUTPUT_DIR/proc_net_tcp6_raw.txt" 2>/dev/null || true

# Função interna para converter hexadecimal de /proc/net/tcp para IP:Porta decimal
decode_proc_tcp() {
    local file="$1"
    [ ! -f "$file" ] && return
    
    awk 'NR>1 {
        split($2, local, ":")
        split($3, remote, ":")
        
        # Converte IP local de Hex para Decimal (Little-Endian)
        ip_loc = sprintf("%d.%d.%d.%d", 
            strtonum("0x" substr(local[1],7,2)), 
            strtonum("0x" substr(local[1],5,2)), 
            strtonum("0x" substr(local[1],3,2)), 
            strtonum("0x" substr(local[1],1,2)))
        port_loc = strtonum("0x" local[2])
        
        # Converte IP remoto
        ip_rem = sprintf("%d.%d.%d.%d", 
            strtonum("0x" substr(remote[1],7,2)), 
            strtonum("0x" substr(remote[1],5,2)), 
            strtonum("0x" substr(remote[1],3,2)), 
            strtonum("0x" substr(remote[1],1,2)))
        port_rem = strtonum("0x" remote[2])
        
        printf "Local: %-21s | Remoto: %-21s | Estado: %s\n", ip_loc ":" port_loc, ip_rem ":" port_rem, $4
    }' "$file"
}

decode_proc_tcp "$OUTPUT_DIR/proc_net_tcp_raw.txt" > "$OUTPUT_DIR/proc_net_tcp_decoded.txt" || true
echo "[+] Tabela de conexoes do kernel decodificada em: proc_net_tcp_decoded.txt"

echo -e "\n=================================================="
echo " 3. ANÁLISE DE INTERFACES E MODO PROMÍSCUO"
echo "=================================================="

# 3.1 Captura estatísticas completas das interfaces
ip -s link > "$OUTPUT_DIR/ip_link_stats.txt" 2>/dev/null || true

# 3.2 Alerta direto se houver interfaces em modo promíscuo (sniffers)
PROMISC_IFACE=$(ip link | grep -i 'PROMISC' || true)
if [ -n "$PROMISC_IFACE" ]; then
    echo "[ALERTA CRÍTICO] Interface em modo PROMÍSCUO detectada!"
    echo "$PROMISC_IFACE" | tee "$OUTPUT_DIR/promisc_interfaces.txt"
else
    echo "[OK] Nenhuma interface em modo promíscuo identificada."
fi

echo -e "\n=================================================="
echo " 4. REGRAS DE FIREWALL E ROOTEAMENTO"
echo "=================================================="

# Verifica se o encaminhamento de IP esta ativo no kernel
IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
if [ "$IP_FORWARD" -eq 1 ]; then
    echo "[ALERTA] Encaminhamento de IP (net.ipv4.ip_forward) esta ATIVADO!"
fi

# Exporta regras do IPTables e Nftables
iptables-save > "$OUTPUT_DIR/iptables_rules.dump" 2>/dev/null || true
nft list ruleset > "$OUTPUT_DIR/nftables_ruleset.dump" 2>/dev/null || true
echo "[+] Regras de firewall exportadas com sucesso."

# -----------------------------------------------------------------
# 5. GERANDO HASHES DE INTEGRIDADE DA COLETA
# -----------------------------------------------------------------
echo -e "\n=================================================="
echo " 5. REGISTRANDO CADEIA DE CUSTÓDIA (SHA-256)"
echo "=================================================="
cd "$OUTPUT_DIR"
sha256sum * > SHA256SUMS 2>/dev/null || true
chmod 440 * 2>/dev/null || true

echo "[+] Todos os relatórios foram bloqueados contra gravação e calculados os hashes."
echo "=================================================="
echo " Triagem concluída. Artefatos gravados em:"
echo " $OUTPUT_DIR"
echo "=================================================="
