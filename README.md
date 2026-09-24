# Guia de Resposta a Incidentes (DFIR) para Sistemas Linux

>_Um guia prático um sobre forense digital e resposta a incidentes (DFIR) em ambientes Linux_

A resposta a incidentes no Linux não se resume a encontrar e remover malware. Trata-se de coletar evidências na ordem correta antes que os artefatos voláteis desapareçam.
Criei este Guia como uma referência para resposta em tempo real (*live-response*) e triagem de sistemas Linux comprometidos. O fluxo de trabalho começa com um princípio simples:
```
Preservar → Coletar → Analisar → Linha do Tempo → Relatar.
```
Esse guia aborda a investigação em 12 etapas:

🔄 **Os Primeiros Cinco Minutos** — preservar evidências, usar binários confiáveis, gravar sua sessão e evitar reiniciar o sistema antes de coletar evidências voláteis.

🧠 **Aquisição de Memória** — coletar o conteúdo da RAM logo no início, pois código injetado, payloads descriptografados, sockets, credenciais e processos excluídos (mas ainda em execução) podem desaparecer após o desligamento.

⚙️ **Processos e /proc** — inspecionar a visão do kernel sobre processos em execução, caminhos de executáveis, linhas de comando, descritores de arquivo e binários excluídos que ainda podem estar sendo executados.

🕸️ **Estado da Rede** — associar sockets a processos e investiguar conexões ativas antes que elas desapareçam.

⏱️ **Buscar por Persistências** — examinar `cron`, timers do `systemd`, chaves SSH, perfis de shell, `LD_PRELOAD`, PAM e outros locais que invasores podem usar para manter o acesso.

📜 **Logs e Histórico do Shell** — correlacionar registros de autenticação, dados do `journal`, registros binários de login, histórico de comandos e lacunas suspeitas, em vez de confiar em uma única fonte.

📈 **Reconstrur a Linha do Tempo** — combinar _timestamps_ MAC (Modificação, Acesso, Criação/Alteração) do sistema de arquivos com logs e outras evidências para determinar o que aconteceu e quando.

🕵️‍♂️ **Buscar por Rootkits** — comparar diferentes visões do sistema em vez de confiar cegamente em utilitários executados em um host potencialmente comprometido.

📦 **Containers e Nuvem** — investigar tanto o host quanto o plano de controle, preservando camadas graváveis ou snapshots antes que evidências efêmeras desapareçam.

🗜️ **Análise de Exfiltração** — correlacionar artefatos de preparação (*staging*), arquivos compactados, tráfego de saída, histórico do shell e atividade na nuvem, distinguindo roubo de dados confirmado de provável.

---

## 1. Os Primeiros Cinco Minutos
>_NÃO DESTRUA AS EVIDÊNCIAS_

O primeiro respondente causa mais danos do que o atacante na maioria dos casos do Linux. Cada comando que você digita grava no histórico do shell, atualiza os horários de acesso e aloca memória. Decida a ordem de coleta antes de tocar no teclado e nunca confie nos binários do próprio host comprometido.
```
NÃO REINICIE -> BINÁRIOS CONFIÁVEIS -> PRESERVE PRIMEIRO
```
---

### Estratégia: Isolar vs. Observar
🔹 Isolar a Rede: Faça isso imediatamente se houver destruição ativa de dados ou exfiltração em andamento.

🔹 Observar Primeiro: Se o cenário estiver suspeito, mas contido, observe e colete a memória RAM antes de cortar os acessos.

🔹 Serviços Críticos: Coordene com os proprietários do serviço. Nunca tome ações unilaterais em ambientes de produção.

🔹 Fique Furtivo: Se o atacante estiver observando, evite rodar comandos defensivos óbvios diretamente no host.
### Ações Imediatas (Antes de Tocar no Teclado)
🔹 Decisão de Isolamento: Defina a estratégia com o líder do incidente antes de agir.

🔹 Kit de Ferramentas: Traga um kit estático e confiável em mídia de somente leitura. Nunca use os binários do host comprometido.

🔹 Preservação de Sessão: Grave toda a sua sessão de comandos. Cada ação deve ser reproduzível e defensável.

🔹 Timestamp: Anote a hora do sistema e o deslocamento do fuso horário como seu primeiro comando.
### Preparação do Ambiente Forense
Antes de rodar qualquer comando de investigação, você precisa garantir que suas próprias ações não destruam evidências ou sejam mascaradas por um rootkit.
#### 1. Desativar o histórico do Shell
``` bash
export HISTFILE=/dev/null; unset HISTFILE
```
#### 2. Gravar a sessão
Registre tudo o que você digitar e receber de saída para fins de auditoria posterior.
```bash
script -a /mnt/forense/session.log
```
#### 3. Usar binários confiáveis:
Não use o `ls`, `ps`, `netstat` ou `lsof` do sistema infectado. Monte um dispositivo externo (ou um compartilhamento somente leitura) com ferramentas estáticas (como o `BusyBox`).
```bash
mount -o ro /dev/sdX1 /mnt/tools # Monta a mídia externa em modo somente leitura
/mnt/tools/busybox ps # Executa a ferramenta estática (BusyBox) a partir da mídia montada
```
Ao ao executar `/mnt/tools/busybox ps`, o analista obtém a lista real de processos diretamente da fonte limpa e segura.
### Ordem de Coleta de Evidências (Ordem de Volatilidade)
Você deve coletar os dados do mais volátil para o menos volátil

🧠 Registros da Memória RAM (DUMP de memória usando ferramentas como LiME).

🕸️ Conexões de rede ativas e sockets abertos.

📂 Processos em execução e arquivos abertos por eles.

👤 Estado do sistema (Uptime, usuários logados).

💽 Dados do disco (Arquivos de log, artefatos no /tmp, etc.).
### Antes de Digitar Qualquer Coisa
O trecho de código abaixo prepara um ambiente seguro para o analista trabalhar sem alterar o sistema comprometido e registrando toda a atividade para fins de cadeia de custódia.
```bash
mount -o ro /dev/sdX1 /mnt/tools # a opção ro=read-only. Use o seu próprio `busybox`
export HISTFILE=/dev/null; unset HISTFILE # Desativa a escrita do histórico de comandos da sessão do terminal.
script -a /mnt/evidence/session.log # registra tudo o que você faz no arquivo session.log
```
### Exemplo de Caso
Um respondente digita 'reboot' em um host suspeito de mineração de criptomoedas para limpá-lo. O payload somente em memória, seu socket C2 e o binário excluído, mas em execução, desaparecem, não deixando nenhuma evidência do vetor de entrada.

### ❌ Erros Comuns a Evitar

 ⏻ Reiniciar ou desligar o sistema antes de realizar a captura da memória RAM (isso apaga payloads em memória e sockets ativos).

 💻 Confiar no host: Executar comandos como `ps`, `ls` ou `netstat` nativos do sistema comprometido (eles podem ter sido adulterados por um Rootkit).

 💽 Poluir o disco: Gravar os dados coletados e logs diretamente no sistema de arquivos do host afetado.

 📝 Falta de registro: Conduzir a investigação sem gravar a sessão, tornando o processo indefensável judicialmente ou em auditorias.
### Ferramentas e Frameworks de Referência
📥 Coleta & Triagem: VAC, CyLR, AVHL, LIMA e validação com sha256sum.

🗃️ Fontes de Dados: Verificação de processos e memória via /proc, auditoria via SIEM e análise de arquivos/diretórios específicos.

📐Normas Técnicas: Alinhado com a RFC 3227 (Ordem de Volatilidade) e NIST SP 800-86 (Guia de Integração de Forense Digital na Resposta a Incidentes).
### Conclusão
Não reinicie a máquina. Não confie nos binários locais. Grave seus passos, use ferramentas estáticas de fora e colete a memória RAM primeiro.

---

## 2. Aquisição de Memória
>_A CAMADA MAIS VOLÁTIL_

A memória RAM deve ser capturada antes de qualquer outra etapa de coleta, pois ela contém dados voláteis cruciais (como códigos injetados e conexões ativas) que nunca serão encontrados em uma imagem de disco.
A memória contém o que o disco jamais conterá: código injetado, payloads descriptografados, sockets C2, credenciais e processos cujos binários foram excluídos após a inicialização. Colete o conteúdo primeiro, transmita-o para fora do host e faça o hash imediatamente para que a cadeia de custódia comece limpa.
```
DESPEJAR RAM -> ENVIAR PARA FORA DO HOST -> ANALISAR POSTERIORMENTE
```
### Regras de Aquisição
🔹 Prioridade máxima: Capture a memória antes de executar outros comandos no host para evitar a corrupção de dados (artefatos).

🔹 Destino seguro: Transmita os dados diretamente para um ouvinte de rede ou mídia externa. Nunca grave o arquivo de dump no disco local do host investigado.

🔹 Integridade e registro: Calcule o hash (ex: sha256sum) imediatamente após a aquisição.

🔹 Registre o horário exato e a versão da ferramenta utilizada.

🔹 Último recurso: Use /proc/kcore apenas se nenhuma ferramenta de captura adequada estiver disponível.
### O Que a Memória Fornece
🔹 Processos fantasma: Execução de binários que já foram deletados do disco.

🔹 Evidências de rede: Conexões de rede que foram fechadas antes da chegada do investigador ao host.

🔹 Manipulação de código: Códigos injetados e chamadas de sistema (syscalls) interceptadas.

🔹 Segredos em cache: Histórico de comandos (como o histórico do bash do Linux), credenciais e chaves criptográficas diretamente do espaço de endereçamento do processo.
### Verifique a RAM com Segurança
O trecho de código abaixo realiza a captura (aquisição) de memória RAM em um sistema Linux e a posterior validação e análise offline da evidência.
```bash
./avml /mnt/evidence/mem.lime # Executa a ferramenta AVML para salvar a memória RAM no arquivo mem.lime
insmod lime.ko 'path="tcp:4444" format=lime' # Carrega o módulo do kernel do LiME (lime.ko) instruindo-o a enviar o dump da memória RAM via rede na porta TCP 4444 no formato LiME.
sha256sum mem.lime > mem.lime.sha256 # Calcula o valor hash do arquivo de memória extraído e o salva
vol3 -f mem.lime linux.pslist / linux.bash / linux.malfind # Executa o Volatility 3 apontando para a imagem de memória capturada (mem.lime) executando plugins de investigação.
```

#### Detalhamento dos Componentes

* **`mount`**: Comando utilitário no Linux usado para anexar o sistema de arquivos de um dispositivo (disco, pendrive, partição) à estrutura principal de diretórios do sistema.
* **`-o ro`**: Flag de opções (`-o`). A opção **`ro`** significa ***read-only*** (somente leitura). Impede qualquer alteração, gravação ou exclusão de dados no dispositivo enquanto ele estiver montado.
* **`/dev/sdX1`**: O arquivo de dispositivo representando a origem.
* **`/dev/sdX`**: Um disco físico (onde o `X` é uma letra genérica como `a`, `b`, `c`).
* **`1`**: A primeira partição daquele disco.
* **`/mnt/tools`**: O ponto de montagem (*mount point*), que é o diretório de destino na árvore de arquivos do sistema onde o conteúdo da partição passará a ser acessível.
* **`linux.malfind`**: O **`malfind`** é um dos plugins mais importantes e utilizados do **Volatility** para a detecção de **malwares e injeção de código** em imagens de memória RAM. Sua função principal é varrer o espaço de memória dos processos em busca de regiões de memória suspeitas que possam conter **código malicioso injetado** (como *DLL injection*, *shellcode* ou *process hollowing*).

#### O que o `malfind` Exibe na Saída

Para cada alerta encontrado, a ferramenta exibe:

* **PID e Nome do Processo**: O processo que abriga a memória suspeita.
* **Endereço de Memória e Tamanho**: A localização exata no espaço de endereçamento do processo.
* **Cabeçalho/Dump em Hexadecimal (Hexdump)**: Os primeiros bytes da região apontada.
* **Desmontagem (Assembly/Disassembly)**: As primeiras instruções em linguagem assembly encontradas naquela área (ex.: chamadas de sistema, *NOP sleds*, etc.).

### Exemplo de Caso
Um host não mostra nada de incomum no disco. O malfind do Volatility na imagem de memória revela uma região injetada em um processo legítimo, e o bash do Linux recupera os comandos digitados pelo atacante literalmente.

### ❌ Erros Comuns a Evitar

🔹 Negligência: Ignorar a coleta de memória achando que a imagem de disco é suficiente.

🔹 Poluição de provas: Gravar o arquivo de saída (dump) dentro do próprio host afetado.

🔹 Falta de documentação: Esquecer de registrar a versão do Kernel (essencial para criar perfis de análise no Volatility).

🔹 Ordem errada: Capturar a memória após rodar dezenas de comandos de triagem, destruindo evidências voláteis.

### Conclusão
Memória primeiro, sempre. Ela contém código injetado, binários deletados, mas em execução, e sockets ativos que nenhuma imagem de disco jamais conterá

---

## 3. Processos e /proc
>_CONFIE NO KERNEL, NÃO NO `ps`_

O conceito central aqui é a confiança nas fontes de dados: ferramentas de espaço do usuário (userland) como `ps`, `ls` e `netstat` podem ser facilmente adulteradas por atacantes, enquanto o diretório `/proc` interage diretamente com o kernel do sistema.
O sistema de arquivos `/proc` é a sua verdade fundamental em um host Linux ativo. Ele expõe o caminho executável real de cada processo, sua linha de comando, seu diretório de trabalho e seus descritores de arquivo abertos, incluindo binários que foram excluídos do disco após a execução.

```
LEIA /proc -> ENCONTRE BINS EXCLUÍDOS -> PERCORRA A ÁRVORE
```
> `ps` PODE ESTAR MENTINDO: Um rootkit de espaço do usuário substitui `ps` e `ls`. O diretório `/proc` do kernel é muito mais difícil de falsificar de forma convincente.

### Enumerar a Partir do KERNEL
O trecho de código abaixo descreve um procedimento clássico de investigação e análise de processos via `/proc` em um sistema Linux comprometido, focado em identificar executáveis ocultos/excluídos do disco e extrair evidências em tempo real.
```
ls -al /proc/*/exe 2>/dev/null | grep deleted # Encontra processos em execução cujos arquivos binários executáveis originais foram apagados do disco rígido.
cat /proc/<PID>/cmdline | tr '\0' ' ' ; echo "" # Exibe a linha de comando exata (com argumentos) usada para iniciar o processo com o PID fornecido.
ls -al /proc/<PID>/cwd # Exibe o diretório de trabalho atual (Current Working Directory) de onde o processo está operando.
ls -al /proc/<PID>/fd # Lista todos os descritores de arquivos (file descriptors) abertos pelo processo.
cp /proc/<PID>/exe /path/to/evidence/recovered_binary.bin # Copia o executável do processo direto da memória e o salva como um arquivo binário em um local seguro.
```
>_Mesmo se o invasor tiver deletado o binário do disco rígido, a imagem do executável permanece acessível através do ponteiro `/proc/<PID>/exe`. Esse código recupera a evidência intacta para posterior engenharia reversa ou submissão ao VirusTotal/YARA._

#### O que verificar em `/proc/[PID]/`

🔹 `/proc/[PID]/exe`: Mostra o link simbólico para o caminho executável real. Se o binário foi apagado do disco pelo atacante enquanto ainda executava, ele exibirá o sufixo (deleted). Você pode copiar esse arquivo para recuperar o binário original

🔹 `/proc/[PID]/cmdline`: Contém a linha de comando completa com os argumentos passados para o processo. Diferente do comando `ps`, o conteúdo aqui não é truncado.

🔹 `/proc/[PID]/fd/`: Diretório com os descritores de arquivos abertos. Permite identificar conexões de rede ativas (sockets) e arquivos manipulados pelo processo.

🔹 Cadeia de execução: Analise o processo pai (PPID), as variáveis de ambiente (`/proc/[PID]/environ`) e a hora de início para alinhar o processo à janela de tempo do incidente.

### Padrões Suspeitos (Indicadores de Comprometimento)

🔹 Diretórios temporários: Processos rodando a partir de `/tmp`, `/dev/shm` ou `/var/tmp`.

🔹 Binários excluídos: Processos rodando a partir de um inode deletado (técnica clássica de fileless malware).

🔹 Falsa identidade: Processos com nomes disfarçados de threads do kernel (ex: entre colchetes como [kworker/0:1]), mas que possuem um caminho executável real associado no `/proc`.

🔹 Anomalia de privilégios/função: Servidores web (ex: Apache, Nginx) ou bancos de dados gerando processos filhos que são shells (`sh`, `bash`).

### Exemplo de Caso
Comparar a saída do `ps` com uma listagem de diretório de `/proc` revela um PID visível em `/proc`, mas oculto do `ps`, que é a assinatura de um rootkit de espaço do usuário interceptando a listagem de processos.
### Erros Comuns a Evitar

🔹 Confiar cegamente em ferramentas nativas como `ps`, `top` ou `netstat` em um sistema potencialmente sob efeito de um rootkit.

🔹 Esquecer de copiar o binário excluído diretamente de `/proc/[pid]/exe` antes de encerrar o processo, perdendo a amostra para análise de malware.

🔹 Negligenciar diretórios baseados em memória RAM (`/dev/shm` e `/run`), locais muito visados para ocultar payloads.

🔹 Deixar de mapear a árvore genealógica completa do processo, prejudicando a reconstrução da linha do tempo do ataque.

### Conclusão
Leia `/proc` em vez de `ps`. Ele revela o caminho executável verdadeiro, recupera binários excluídos ainda em execução e expõe o que `ps` foi configurado para ocultar.
Em sistemas suspeitos, consulte o diretório `/proc` diretamente. Se o comando `ps` omitir um PID que está listado dentro de `/proc`, você está lidando com um rootkit que intercepta e mascara as chamadas de listagem de processos.

---

## 4. Estado da Rede
>_COM QUEM ESTÁ SE COMUNICANDO_

O estado da rede em tempo real vincula um processo suspeito a um destino externo, que geralmente é a rota mais rápida para confirmar a violação. Capture-o cedo, porque os sockets fecham, e correlacione o endereço do par com seus logs de saída para obter o quadro completo.

```
LISTAR SOCKETS -> MAPEAMENTO PARA PROCESSO -> VERIFICAR O PAR
```

>_OS SOCKETS MORREM RAPIDAMENTE: Um beacon que verifica a cada cinco minutos pode não mostrar nenhuma conexão no momento em que você verifica_

### O que Coletar

🔹 Todos os sockets em escuta e estabelecidos com seus respectivos PIDs

🔹 Tabelas raw/proc/net como verificação cruzada com ferramentas interceptadas

🔹 Regras de firewall atuais, já que os invasores costumam adicionar regras de permissão ou redirecionamento

🔹 Cache ARP, tabela de roteamento e quaisquer interfaces de túnel inesperadas

### Capturar Comexões e Proprietários
As conexões de rede são efêmeras e os sockets fecham rápido, o que exige rapidez do analista para capturar a evidência antes que ela desapareça.
O trecho de código baixo reúne comandos essenciais para auditoria e investigação de rede em tempo real em um servidor Linux. O objetivo é mapear conexões ativas, relacioná-las a processos, verificar a tabela bruta do kernel, checar o estado das interfaces física/virtuais e inspecionar as regras do firewall.
```
ss -antpu #todos os TCP/UDP, numérico, com o processo proprietário. Substitui o netstat
lsof -i -n -P # Lista arquivos abertos (no Linux, sockets são tratados como arquivos). Verificação cruzada ss
cat /proc/net/tcp /proc/net/tcp6 # É onde o kernel armazena o estado bruto das conexões. A "verdade fundamental".
ip -s link # Mostra as interfaces de rede (para ver se há interfaces em modo promíscuo ou placas virtuais estranhas).
iptables-save; nft list ruleset # Despejam na tela todas as regras ativas de firewall (Netfilter/Nftables).
```
### Resumo da Estratégia de Análise

| Camada de Análise | Comando | O que revela |
| --- | --- | --- |
| **Visão do Usuário** | `ss -antpu` | Conexões mapeadas para nomes de processos e PIDs. |
| **Visão de Processo/Arquivo** | `lsof -i -n -P` | Descritores de arquivo de rede abertos por processos. |
| **Visão Bruta do Kernel** | `cat /proc/net/tcp` | Estado real e inalterado da tabela de sockets no kernel. |
| **Camada Física/Enlace** | `ip -s link` | Módulos promíscuos (*sniffers*) e interfaces suspeitas. |
| **Filtragem de Tráfego** | `iptables-save` / `nft` | Redirecionamentos, NATs e exceções no firewall. |

>_Os IPs e portas de `/proc/net/tcp` estão em hexadecimal e podem ser convertidos para formato legível_

### Sinais de Alerta

🔹 Portas Altas: Sockets abertos em portas incomuns associados a binários ocultos em `/tmp`, `/var/tmp` ou `/dev/shm`.

🔹 Conexão de saída para um ASN de hospedagem ou VPS sem motivo comercial

🔹 Cadência regular de beacon visível no proxy ou Netflow em vez de no host

🔹 Novas regras de iptables ou uma interface de túnel que ninguém provisionou

### Exemplo de Caso
Uma única conexão estabelecida de um processo em execução a partir de `/dev/shm` para um endereço VPS confirma o caso. Os logs do proxy mostram o mesmo peer contatado a cada 300 segundos por onze dias.

### ❌ Erros Comuns a Evitar

🔹 Confiar apenas no estado do host para um beacon que está atualmente ocioso

🔹 Usar netstat do host comprometido sem verificação cruzada

🔹 Não capturar regras de firewall, entradas de permissão adicionadas pelo atacante ausentes

🔹 Ignorar sockets de domínio UNIX usados ​​para C2 local entre processos

### Conclusão
Capture sockets antecipadamente e mapeie-os para os processos proprietários, mas corrobore com telemetria de rede, pois um beacon ocioso não mostra nada no host.

---

