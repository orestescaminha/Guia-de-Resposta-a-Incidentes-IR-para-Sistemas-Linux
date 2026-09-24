### **Como Utilizar**

1. **Torne o script executável e crie a Baseline Inicial:**
Execute como `root` (ou com `sudo`) para garantir leitura de arquivos protegidos em `/root` e `/etc`:
```bash
chmod +x monitor_persistencia.py
sudo ./monitor_persistencia.py --init

```

2. **Execute Verificações Periódicas:**
Rodar sem argumentos aciona o modo de auditoria:
```bash
sudo ./monitor_persistencia.py

```

3. **Automatize via Systemd Timer ou Cron:**
Para rodar a verificação a cada 1 hora e salvar a saída em um arquivo de log:
```bash
# Adicione ao /etc/crontab:
0 * * * * root /caminho/para/monitor_persistencia.py >> /var/log/persistencia_audit.log 2>&1

```
