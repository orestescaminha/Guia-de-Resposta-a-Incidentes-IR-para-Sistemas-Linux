#!/usr/bin/env bash
# Script de Triagem Forense e Auditoria de Histórico de Shells
set -euo pipefail

OUTPUT_DIR="/tmp/history_audit_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " 1. MAPEANDO ARQUIVOS DE HISTÓRICO ENCONTRADOS"
echo "=================================================="
# Busca arquivos de histórico de bash, zsh, python, mysql, etc.
find /home /root -maxdepth 3 \( -name "*_history" -o -name ".bash_history" -o -name ".zsh_history" \) -ls 2>/dev/null | tee "$OUTPUT_DIR/history_files_list.txt"

echo -e "\n=================================================="
echo " 2. CHECANDO ADULTERAÇÃO (TAMPERING / SIZE 0 / SYMLINKS)"
echo "=================================================="
find /home /root -maxdepth 3 \( -name "*_history" -o -name ".zsh_history" \) 2>/dev/null | while read -r hist_file; do
    # Verifica link simbólico apontando para /dev/null
    if [ -L "$hist_file" ]; then
        target=$(readlink "$hist_file")
        if [ "$target" = "/dev/null" ]; then
            echo "[ALERTA CRÍTICO] $hist_file é um link simbólico para /dev/null!"
        fi
    # Verifica arquivos esvaziados (0 bytes)
    elif [ -f "$hist_file" ] && [ ! -s "$hist_file" ]; then
        echo "[ALERTA] $hist_file existe mas está com TAMANHO ZERO!"
    fi
done

echo -e "\n=================================================="
echo " 3. BUSCANDO TENTATIVAS DE SUPRESSÃO EM CONFIGURAÇÕES"
echo "=================================================="
# Procura alterações em arquivos de inicialização de shell de todos os usuários
find /home /root -maxdepth 3 \( -name ".*rc" -o -name ".profile" -o -name "*.sh" \) -type f 2>/dev/null | xargs grep -Ein 'HISTFILE|HISTSIZE|HISTFILESIZE|set \+o history|unset HISTFILE' 2>/dev/null || echo "Nenhuma diretiva suspeita encontrada nos arquivos rc."

echo -e "\n=================================================="
echo " 4. EXTRAINDO E CONSOLIDANDO COMANDOS HISTÓRICOS"
echo "=================================================="
# Consolida todos os históricos encontrados em um único arquivo com identificação do usuário
find /home /root -maxdepth 3 \( -name "*_history" -o -name ".zsh_history" \) -type f -s 2>/dev/null | while read -r hist_file; do
    echo -e "\n--- INÍCIO: $hist_file ---" >> "$OUTPUT_DIR/consolidated_history.txt"
    cat "$hist_file" >> "$OUTPUT_DIR/consolidated_history.txt" 2>/dev/null || true
done
echo "[+] Histórico consolidado salvo em: $OUTPUT_DIR/consolidated_history.txt"

echo -e "\n=================================================="
echo " 5. MEMÓRIA RAM (VOLATILITY 3)"
echo "=================================================="
if [ -f "mem.lime" ] && command -v vol3 &>/dev/null; then
    echo "[+] Imagem de memória 'mem.lime' encontrada. Executando plugin linux.bash..."
    vol3 -f mem.lime linux.bash > "$OUTPUT_DIR/volatility_bash_memory.txt" 2>&1
    echo "[+] Resultado do Volatility salvo em: $OUTPUT_DIR/volatility_bash_memory.txt"
else
    echo "[!] pmem/mem.lime ou Volatility 3 não encontrado no diretório atual. Etapa de RAM ignorada."
fi
