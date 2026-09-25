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

## 🚫 Erros Comuns a Evitar

 ⏻ Reiniciar ou desligar o sistema antes de realizar a captura da memória RAM (isso apaga payloads em memória e sockets ativos).

 💻 Confiar no host: Executar comandos como `ps`, `ls` ou `netstat` nativos do sistema comprometido (eles podem ter sido adulterados por um Rootkit).

 💽 Poluir o disco: Gravar os dados coletados e logs diretamente no sistema de arquivos do host afetado.

 📝 Falta de registro: Conduzir a investigação sem gravar a sessão, tornando o processo indefensável judicialmente ou em auditorias.

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

### 🚫 Erros Comuns a Evitar

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

```Bash
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

### 🚫 Erros Comuns a Evitar

🔹 Confiar cegamente em ferramentas nativas como `ps`, `top` ou `netstat` em um sistema potencialmente sob efeito de um rootkit.

🔹 Esquecer de copiar o binário excluído diretamente de `/proc/[pid]/exe` antes de encerrar o processo, perdendo a amostra para análise de malware.

🔹 Negligenciar diretórios baseados em memória RAM (`/dev/shm` e `/run`), locais muito visados para ocultar payloads.

🔹 Deixar de mapear a árvore genealógica completa do processo, prejudicando a reconstrução da linha do tempo do ataque.

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

```Bash
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

### 🚫 Erros Comuns a Evitar

🔹 Confiar apenas no estado do host para um beacon que está atualmente ocioso

🔹 Usar netstat do host comprometido sem verificação cruzada

🔹 Não capturar regras de firewall, entradas de permissão adicionadas pelo atacante ausentes

🔹 Ignorar sockets de domínio UNIX usados ​​para C2 local entre processos

---

## Busca por Persistências

>_DOZE LUGARES PARA PROCURAR_

O Linux oferece um amplo menu de locais de persistência e a maioria dos respondentes verifica apenas dois. Trabalhe com uma lista escrita sempre, porque o invasor que deixou um cron job quase certamente também deixou uma chave SSH, uma unidade systemd ou uma modificação de perfil de shell.

```
VERIFIQUE TODOS -> TEMPORIZADORES CRON -> CHAVES SSH
```

❗ UM ÚNICO LOCAL NUNCA É APENAS UM: Invasores competentes instalam vários mecanismos. Encontrar um e pará-lo é como você é reinfectado.

Um erro clássico de equipes de resposta a incidentes: encontrar um único mecanismo de persistência, removê-lo e achar que o problema está resolvido, quando na verdade os atacantes costumam espalhar múltiplos pontos de acesso para garantir o retorno. Preparei uma versão organizada dos comandos citados para você copiar e usar

Abaixo estão **12 locais críticos de persistência** em ambientes Linux, organizados pelas principais técnicas empregadas por atacantes:

---

### **12 locais críticos de persistência**

#### **1. Agendadores de Tarefas (Cron Jobs)**

* **`/etc/crontab` e `/etc/cron.*` (`cron.d`, `cron.daily`, `cron.hourly`, `cron.monthly`, `cron.weekly`)**: Arquivos de configuração global do cron do sistema.
* **`/var/spool/cron/crontabs/`** *(ou `/var/spool/cron/` dependendo da distro)*: Diretórios que armazenam os *crontabs* individuais de cada usuário do sistema (incluindo `root`).

#### **2. Configurações e Chaves de Acesso SSH**

* **`~/.ssh/authorized_keys` e `~/.ssh/authorized_keys2**`: Arquivos no diretório de cada usuário que armazenam chaves públicas autorizadas a realizar login sem senha via SSH.
* **`/etc/ssh/sshd_config` e `/etc/ssh/sshd_config.d/**`: Arquivos de configuração do daemon SSH. Podem ser alterados para aceitar senhas mestras, desativar logs ou incluir opções de execução remota como `AuthorizedKeysCommand`.

#### **3. Serviços do Gerenciador de Inicialização (Systemd)**

* **`/etc/systemd/system/` e `/lib/systemd/system/**`: Locais onde ficam os arquivos de unidade (`.service`, `.timer`, `.path`) criados ou modificados para executar binários maliciosos na inicialização ou em intervalos regulares.
* **`~/.config/systemd/user/`**: Diretório onde o *systemd* permite que usuários comuns (sem privilégios de root) configurem e executem serviços persistentes específicos no escopo do usuário.

#### **4. Inicialização de Perfil de Shell**

* **`/etc/profile`, `/etc/profile.d/`, `/etc/bash.bashrc` e `/etc/zsh/zshrc**`: Arquivos de inicialização global do shell. Qualquer script inserido aqui é executado sempre que qualquer usuário abre uma nova sessão de terminal.
* **`~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.zshrc**`: Arquivos de configuração de shell específicos do diretório pessoal de cada usuário (`/root/` ou `/home/<usuario>/`).

#### **5. Scripts de Inicialização Legados e Invocadores de Sistema**

* **`/etc/rc.local`**: Arquivo de script executado ao final do processo de boot em sistemas com compatibilidade SysVinit/Systemd.
* **`/etc/init.d/` e `/etc/rc*.d/**`: Scripts de inicialização legados (*SysVinit*) e links simbólicos associados aos *runlevels* do sistema.

#### **6. Módulos do Kernel e Injeções de Bibliotecas**

* **`/etc/ld.so.preload`**: Arquivo de configuração que força o carregador do sistema a pré-carregar bibliotecas dinâmicas (`.so`) antes de qualquer outra. Bastante utilizado por *userland rootkits*.
* **`/lib/modules/$(uname -r)/` e `/etc/modules-load.d/**`: Locais de armazenamento e carregamento automático de módulos do kernel (LKMs) durante a inicialização.

---

### **Resumo dos Locais para Triagem Rápida**

| Categoria | Caminho do Sistema | Método de Verificação Rápida |
| --- | --- | --- |
| **Cron** | `/etc/cron*` e `/var/spool/cron/crontabs/*` | `crontab -l` e `cat /etc/crontab` |
| **SSH** | `~/.ssh/authorized_keys` | `head -n 50 /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys` |
| **Systemd** | `/etc/systemd/system/` | `systemctl list-unit-files --state=enabled` |
| **Shell** | `/etc/profile.d/*` e `~/.bashrc` | `debsums` / `rpm -Vc` ou inspeção por hashes |
| **Biblioteca** | `/etc/ld.so.preload` | `cat /etc/ld.so.preload` (se existir, deve ser analisado com cuidado) |


Abaixo, uma sequência de comandos em uma única linha (one-liner) desenvolvida para inspecionar e auditar rapidamente os 12 locais de persistência em um servidor Linux.

---

### Inspecionar e Auditar Rapidamente

O comando usa um cabeçalho visual para separar cada seção e redireciona erros de permissão ou arquivos inexistentes (`2>/dev/null`):
Para salvar todo o resultado em um arquivo com data para anexar ao relatório de triagem ou cadeia de custódia, adicionei `| tee audit_persistencia_$(date +%Y%m%d).log` ao final do comando:

```Bash
sudo sh -c 'for d in "/etc/crontab /etc/cron* /var/spool/cron/crontabs/*" "/root/.ssh/authorized_keys /home/*/.ssh/authorized_keys /etc/ssh/sshd_config" "/etc/systemd/system/*.service /lib/systemd/system/*.service /home/*/.config/systemd/user/* /root/.config/systemd/user/*" "/etc/profile /etc/profile.d/* /etc/bash.bashrc /root/.bashrc /root/.bash_profile /home/*/.bashrc" "/etc/rc.local /etc/init.d/* /etc/rc*.d/*" "/etc/ld.so.preload /etc/modules-load.d/*"; do echo -e "\n=== AUDITANDO: $d ==="; ls -la $d 2>/dev/null; done' | tee audit_persistencia_$(date +%Y%m%d).log

```

---

### **One-Liners Específicos para Auditoria Rápida de Conteúdo**

Se além de listar a existência dos arquivos você quiser **visualizar o conteúdo útil** (desconsiderando linhas vazias ou comentários), utilize estes utilitários focados em cada categoria:

#### **1. Tarefas Agendadas (Cron Jobs)**

```bash
echo "=== CRON JOBS ==="; cat /etc/crontab /etc/cron.*/* /var/spool/cron/crontabs/* 2>/dev/null | grep -v "^#" | grep -v "^$"

```

#### **2. Chaves SSH e Configuração**

```bash
echo "=== SSH KEYS ==="; head -n 100 /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null

```

#### **3. Serviços Systemd Habilitados (Persistência no Boot)**

```bash
echo "=== SYSTEMD SERVICES ==="; systemctl list-unit-files --state=enabled 2>/dev/null | head -n 30

```

#### **4. Perfis de Shell (Injeção de Comandos)**

```bash
echo "=== SHELL PROFILES ==="; grep -v "^#" /etc/profile /etc/profile.d/* /etc/bash.bashrc /root/.bashrc /home/*/.bashrc 2>/dev/null | grep -v "^$"

```

#### **5. Preload de Bibliotecas (Rootkits em Userland)**

```bash
echo "=== PRELOAD ==="; [ -f /etc/ld.so.preload ] && cat /etc/ld.so.preload || echo "Nenhum ld.so.preload encontrado"

```

---

### Automatizar o Monitoramento Contínuo

Para automatizar o monitoramento contínuo dos 12 locais de persistência, a melhor abordagem é calcular e salvar o **hash SHA-256** do conteúdo dos arquivos e diretórios críticos em uma linha de base (*baseline*). Em execuções subsequentes, o script compara a baseline antiga com o estado atual e alerta se um arquivo foi **criado**, **modificado** ou **removido**.
O script em Python 3 [monitor_persistencia.py](https://github.com/orestescaminha/Guia-de-Resposta-a-Incidentes-IR-para-Sistemas-Linux/blob/main/scripts/monitor_persistencia.py) é uma solução completa , pronta para produção e sem dependências externas.

---

## Leia os Logs

>_auth, journald, wtmp_

A autenticação do Linux e o histórico de sessão residem em vários arquivos com formatos diferentes. Leia-os juntos: auth.log ou secure para tentativas de autenticação, journald para detalhes em nível de serviço e os binários `wtmp`, `btmp` e `lastlog` para registros de sessão.

```
RASTREAMENTO DE AUTENTICAÇÃO -> QUEM FEZ LOGIN -> VERIFIQUE SE HÁ LACUNAS
```

>❗ LACUNAS TAMBÉM SÃO EVIDÊNCIAS: Uma hora faltando no `auth.log` ou um `wtmp` truncado é, por si só, uma descoberta, não um inconveniente.

Os comandos abaixo abrangem muito bem a base tradicional de auditoria no Debian/Ubuntu e RHEL.

```Bash
grep -Ei 'accepted|failed|invalid user' /var/log/auth.log # Debian; segure no RHEL
journalctl -u sshd -since 2026-09-01 --no-pager # detalhes do nível de serviço
last -Faixw; lastb -Fa # wtmp (sucesso) + btep (falha) # registros de sessão binária
grep -E 'sudo:.*COMMAND=' /var/log/auth.log # trilha de escalonamento de privilégios
```

Porém, pode ser aprimorado para resolver _issues_ como: Incompatibilidade de Distros e Log Rotation; Busca apenas nos logs ativos ignorando logs rotacionados (ex.: auth.log.1, auth.log.2.gz); Ignora Eventos Ocultos e exige Análise Manual do `last/lastb`.

Para elevar esse processo a um nível profissional de resposta a incidentes, a correlação de logs precisa ser automatizada e estendida a outros vetores de autenticação que frequentemente passam despercebidos (como su, sessões PAM, SSH por chave pública e falhas de sudo).

O script [coleta_auth.sh](https://github.com/orestescaminha/Guia-de-Resposta-a-Incidentes-IR-para-Sistemas-Linux/blob/main/scripts/coleta_auth.sh) é uma versão melhorada que analisa tentativas de autenticação e eventos de elevação de privilégio, verifica a integridade dos logs binários e exibe logins e falhas recentes.

## Histórico do Shell

>_O QUE ELES DIGITARAM_

Aqui, o foco principal é a análise de histórico de comandos (shell history) para rastrear ações de atacantes.
O histórico do shell é o artefato de maior valor quando sobrevive, fornecendo os comandos exatos do atacante. Verifique cada usuário, procure os truques usados ​​para suprimi-lo e lembre-se de que o histórico não gravado ainda pode ser recuperado da memória.

```
ENCONTRAR HISTÓRICOS -> VERIFICAR TRUQUES -> TEMPO DE RECUPERAÇÃO
```

>❗ UM HISTÓRICO É FACILMENTE DERROTADO: Os atacantes desativam HISTFILE, o vinculam (_link simbólico_) ao `/dev/mull` ou simplesmente o excluem, portanto, a ausência não prova nada.

### Comandos para Coletar e Avaiar o Histórico

O fluxo de trabalho dos commandos abaixo, abrange os principais pontos de falha no rastreamento de histórico (arquivos no disco, tampering via links/tamanho zero, desativação de variáveis de ambiente e recuperação volátil da RAM).

```Bash
find /home /root -name "*_history" -exec ls -la {} \; # Encontrar Históricos de Comandos. Todos os usuários, todos os shells
ls -la ~/.bash_history # size 0 ou -> /dev/null = tampering # the tell
grep -rn 'HISTFILE\|HISTSIZE\|set +o history' /home /root/.*rc # tentativas de supressão
vol3 -f mem.lime linux.bash # recuperar histórico não gravado # memória supera exclusão
```

A Bash acima merece uma explicação rápida:

**Linha 1**: Encontrar Históricos de Comandos
Mapea as ações de um invasor. O analista busca os arquivos onde o shell armazena os comandos digitados, como `.bash_history`, `.zsh_history` ou `.sh_history`, no diretório de cada usuário.

**Linha 2**: Ocultação de rastros (tampering)
Lista informações detalhadas (-l) e inclui arquivos ocultos (-a) sobre o arquivo `.bash_history` localizado no diretório pessoal do usuário (~).

Os comentários `# size 0 ou -> /dev/null = tampering # the tell` explica o que procurar na saída do comando para identificar se o histórico de comandos foi adulterado:

🔹 **size 0**: Se o arquivo existir mas tiver 0 bytes de tamanho, significa que o histórico foi apagado (ex.: usando cat /dev/null > ~/.bash_history ou truncate).

🔹 **-> /dev/null**: Se a saída mostrar um link simbólico apontando para /dev/null (ex.: .bash_history -> /dev/null), significa que o invasor redirecionou permanentemente o histórico para um "buraco negro", impedindo que qualquer comando seja gravado.

🔹 **= tampering**: Qualquer uma das duas situações acima indica adulteração/manipulação (tampering). Em auditoria de segurança, administradores normais não limpam ou desativam seus históricos de comandos sem um motivo explícito.

🔹 **# the tell**: Termo em inglês vindo do pôquer ("o indício" ou "a pista"). Significa que essa anomalia é a evidência clara que denuncia que alguém tentou esconder as ações realizadas no sistema.

**Linha 3**: Verificar Truques de Supressão (Antiforense)
Atacantes frequentemente tentam evitar que seus comandos sejam salvos. Aqui, aponto duas formas de detectar isso:

🔹 Modificações de configuração: Eles desativam as variáveis de ambiente ou reduzem seu tamanho para zero.

🔹 Links para o limbo: Um truque comum é apontar o arquivo de histórico para `/dev/null`, fazendo com que todos os comandos digitados sejam descartados instantaneamente. Um arquivo com tamanho `0` ou linkado para o `/dev/null` é um forte indício de adulteração.

**Linha 4**: Recuperação via Memória (RAM)
Se o atacante deletou o arquivo ou impediu a gravação no disco, os comandos ainda podem estar ativos na memória RAM do processo do shell (`bash`).

🔹 Análise de Volatility: O _ Volatility 3_ (`vol3`), é uma ferramenta de forense de memória.
O argumento `mem.lime` é usado quando a memória é capturada utilizando o módulo de kernel LiME (Linux Memory Extractor) no seu formato nativo (format=lime).

---

### Script Automatizado

Para transformar esses comandos em um **script de triagem automatizado e robusto**, adicionei verificações para outras shells usadas por atacantes (como `zsh`, `fish` e `sh`).
O script [audit_history.sh](https://github.com/orestescaminha/Guia-de-Resposta-a-Incidentes-IR-para-Sistemas-Linux/blob/main/scripts/audit_history.sh) automatiza a coleta no disco, verifica evidências de adulteração e gera um relatório claro.

### **Automação e Proteção do Histórico em Tempo Real**

Se você gerencia o servidor e quer **impedir** que atacantes apaguem o histórico no futuro:

1. **Tornar o `.bash_history` apenas para adição (*append-only*)**:
```bash
chattr +a /home/*/.bash_history /root/.bash_history

```

Isso impede que o usuário apague ou sobrescreva o arquivo (mesmo com `cat /dev/null >`).

2. **Forçar gravação imediata e timestamp via `/etc/bash.bashrc**`:
Adicione as seguintes linhas na configuração global do Bash para garantir que cada comando seja gravado instantaneamente com data e hora:
```bash
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "
export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

```

### O Mistério do Histórico Vazio

Em investigações cibernéticas, a ausência de evidências costuma ser, por si só, uma evidência crucial. Um dos truques mais velhos e comuns utilizados por atacantes para ocultar suas pegadas em sistemas Linux é vincular o arquivo `.bash_history` (ou equivalentes) ao `/dev/null`. Quando isso acontece, todo comando digitado desaparece instantaneamente, deixando o arquivo de histórico permanentemente vazio.
No entanto, o que parece um "beco sem saída" pode se tornar um ponto de virada graças à perícia forense de memória. Mesmo que o atacante tenha desativado a gravação em disco ao apontar o histórico para o `/dev/null`, o buffer de histórico em processo pode continuar ativo na memória RAM. Através da análise forense da imagem da memória com o Volatility 3 (utilizando o plugin _bash_), o analista consegue extrair o buffer intacto, recuperando da sequência completa de comandos digitados pelo invasor, incluindo a URL exata de download do servidor de Comando e Controle (C2), por exemplo.

🛠️ Técnicas de Recuperação:
Se você abrir o histórico e ele estiver zerado ou ausente, ative o plano de contingência imediatamente através destas quatro frentes:

[Histórico Apagado]

       │
       ├─► 🧠 Memória RAM ────────► Recuperar buffer em processo (Volatility 3 + plugin bash)
       ├─► 📋 Auditd ─────────────► Reconstruir logs se o registro 'execve' estiver ativo
       ├─► 🔐 Logs do Sudo ───────► Capturar entradas COMMAND independentemente do shell
       └─► ⏳ Linha do Tempo ─────► Usar Sleuth Kit para inferir ações via MACB do filesystem

🔹 Recuperação de Memória: Extraia o buffer volátil do processo do shell usando ferramentas de análise de memória (como o Volatility).

🔹 Reconstrução via Auditd: Se o monitoramento do sistema estiver ativado com regras para a chamada de sistema execve, cada comando executado estará registrado de forma centralizada nos logs do auditor.

🔹 Logs de Sudo: Monitore os logs de autenticação e elevação de privilégio. O sudo captura as entradas COMMAND diretamente, não importando o que o usuário faça com o histórico do shell.

🔹 Linha do Tempo do Sistema de Arquivos (Timeline): Utilize ferramentas como o Sleuth Kit para montar uma linha do tempo dos metadados dos arquivos (UAC/CyLR/MACB). Alterações em arquivos de configuração e binários ajudam a inferir a sequência de ações

### 🚫 Erros Comuns a Evitar

🔹 Concluir que nada aconteceu porque o histórico está vazio

🔹 Verificar apenas o histórico do root e omitindo a conta de serviço usada

🔹 Sobrescrever o histórico ao executar seus próprios comandos como esse usuário

🔹 Não correlacionar o histórico com os logs do `auditd` ou `sudo` para identificar lacunas

