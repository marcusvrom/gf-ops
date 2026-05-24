# ops/install — `install` hardened

Substituto do script `install` original (`docs/install-original-reference.txt`).
Endereça os 5 riscos listados no `CLAUDE.md` §6 e os mapeia para mudanças concretas.

## Comparação rápida

| Risco do `install` original | Endereçamento aqui |
|---|---|
| 🔴 `chmod 777 /root -R` (2x) | **Removido**. `05-server-config.sh` deixa o tree do servidor `0750 root:root`; binários `0750`, demais arquivos `0640`, `setup.ini` `0600`. |
| 🔴 `listen_addresses='*'` + `pg_hba 0.0.0.0/0 md5` | `02-postgres.sh` ancora `listen_addresses = 'localhost'`, remove regras `0.0.0.0/0` se presentes, e adiciona linhas `scram-sha-256` só para `127.0.0.1/32` e `::1/128`. |
| 🔴 Servidor conecta como superusuário `postgres` | Cria role `gf_app` `NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT`. Os bancos passam a ter `OWNER = gf_app`. `setup.ini` aponta para `gf_app`. |
| 🟡 Senha em texto plano via `sed` | Senha vive em `/etc/gf-server/env` (`0600 root:root`). Os scripts a lêem de lá. O painel reescrito também lê via `getenv`. Os `setup.ini` continuam sendo arquivos em disco — limitação dos binários ELF — mas com `0600 root:root`. |
| 🟡 `apt purge` destrutivo no modo `full` | **Não purgamos** nada. `01-os-prereqs.sh` só instala/ajusta o que falta. |

## Estrutura

```
ops/install/
├── README.md
├── lib.sh                  # helpers (log, env, sql_lit, psql_super)
├── env.example             # template para /etc/gf-server/env
├── install.sh              # orquestrador (passo-a-passo com confirmação)
├── 01-os-prereqs.sh        # i386, libs 32-bit, nscd, locale C, nsswitch
├── 02-postgres.sh          # PG 13 do apt.postgresql.org, hardened + role gf_app
├── 03-databases.sh         # cria 3 bancos OWNER gf_app, carrega .sql, sequence MVP
├── 04-ip-patch.sh          # patch hex de IP com .bak + audit sha256
├── 05-server-config.sh     # render setup.ini (0600) + perms do tree
└── 06-web.sh               # deploy do painel reescrito em /var/www/gf-panel, vhost
```

Os scripts são **idempotentes**: re-rodar não corrompe estado. Onde a operação é
destrutiva por natureza (recriar bancos), há flag explícita (`03-databases.sh --reset`)
com confirmação interativa.

## Setup mínimo

```bash
# 1) Segredo
sudo mkdir -p /etc/gf-server
sudo cp ops/install/env.example /etc/gf-server/env
sudo chmod 600 /etc/gf-server/env
sudo chown root:root /etc/gf-server/env
sudo $EDITOR /etc/gf-server/env   # GF_DB_PASSWORD, GF_SERVER_HOST_IP, ...

# 2) Rodar tudo, com confirmação por etapa
sudo bash ops/install/install.sh

# Ou passos individuais (idempotente):
sudo bash ops/install/01-os-prereqs.sh
sudo bash ops/install/02-postgres.sh
sudo bash ops/install/03-databases.sh
sudo bash ops/install/04-ip-patch.sh
sudo bash ops/install/05-server-config.sh
sudo bash ops/install/06-web.sh
```

## Decisões e trade-offs

### Por que **um** role `gf_app`, não três (`gf_gs_app` / `gf_ls_app` / `gf_ms_app`)?
O `setup.ini` dos binários aceita user/senha por banco (`GameDBUser`/`AccountDBUser`),
então **dá** para split. Não fiz agora porque:
- O painel reescrito conecta nos 3 bancos com a mesma config (`getenv('GF_DB_USER')`),
  então split exigiria 3 conjuntos de credenciais no painel também.
- O ganho de isolamento é marginal num MVP onde o WorldServer já fala com 2 bancos.
- A passagem para 3 roles é uma migração SQL pura (`CREATE ROLE` + `REASSIGN OWNED`),
  trivial quando passar a fazer sentido (clusters separados, auditoria distinta).

### Por que `scram-sha-256`, não `md5`?
É o default do PG 13+, mais forte que md5. Continua funcionando com `password_encryption=scram-sha-256`
(default) — o `ALTER ROLE ... PASSWORD` re-gera o hash no formato configurado.
Se algum cliente legado ficar incapaz de fazer SCRAM (não é o caso de `libpq` recente
nem de `tokio-postgres` nem do PDO-pgsql moderno), volte a linha para `md5`.

### Por que **não** mexer no `postgres` superuser?
O install original sobrescrevia a senha do `postgres` com a senha do app. Aqui
deixamos o `postgres` intacto (autenticação `peer` local = só root via `sudo -u postgres`).
O install hardened só usa `postgres` em operações administrativas (criar role/banco,
carregar `.sql`). A senha do `gf_app` muda; a do `postgres`, não.

### Senha do DB em `setup.ini` — limitação aceita
Os binários do GameServer **lêem `setup.ini` em texto** e não suportam variáveis de
ambiente. Não dá pra eliminar a senha em disco sem um wrapper que materialize o arquivo
no boot. Mitigação real: `0600 root:root` no `setup.ini`, `0750 root:root` no diretório,
e no `ops/systemd/` (item 1 do backlog) o serviço roda como root mesmo.
Próximo passo natural (não neste item): `tmpfs` para `setup.ini` materializado a partir
de `/etc/gf-server/env` no `ExecStartPre=` da unit.

### Patch de IP
- Mantém o **mesmo** layout de bytes do script original (`ascii_hex_do_ip_de_rede + 3 null bytes`),
  para garantir compatibilidade dos binários.
- `.bak` é criado **só na primeira vez**: re-rodar não pisa no original.
- Cada patch grava sha256 antes/depois em `/var/lib/gf-server/ip-patch.log` (auditoria).
- `--dry-run` imprime o plano sem escrever.
- Recusa rodar com IP loopback (cliente em outra máquina jamais alcança 127.0.0.1).

### `06-web.sh` substitui o `/var/www/html/*.php` legado
Remove os PHP antigos (SQLi em todos os endpoints) e instala o painel reescrito de
`web/` em `/var/www/gf-panel/`, com `DocumentRoot=public/` (lib/, migrations/, bin/
e config.local.php ficam **fora** do escopo do Apache). Roda as migrations (sequence
e `panel_admins`) e reasigna ownership para `gf_app`.

## Verificação pós-install

```bash
# PG aceitando só local
ss -ltnp | grep -E ':(5432)\b'   # esperado: bind em 127.0.0.1 (e ::1)

# Role gf_app criado e sem privilégio
sudo -u postgres psql -c '\du gf_app'

# Bancos com ownership correto
sudo -u postgres psql -c '\l' | grep -E 'gf_(gs|ls|ms)'

# Permissões do tree (esperado: drwxr-x---  root root)
stat -c '%A %U:%G %n' /root/gf_server

# setup.ini sem leitura para 'others'
stat -c '%A %U:%G %n' /root/gf_server/setup.ini  # -rw-------

# Audit do patch
cat /var/lib/gf-server/ip-patch.log
```

## O que ainda NÃO está aqui (próximos backlogs)

- Rotação automática da senha de `gf_app` — quando houver Ansible/CD.
- Hashing de `setup.ini` em tmpfs com `ExecStartPre=` (esconde a senha do disco persistente).
- 3 roles isolados por banco.
- Firewall (ufw/nftables) — fora do escopo do `install`, vai junto da observabilidade (item 5).
