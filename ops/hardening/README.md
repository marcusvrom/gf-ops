# ops/hardening — duas roles de privilégio mínimo, localhost-only, md5 legado

Refina o trabalho de `ops/install/` substituindo a role única `gf_app` (superset
de tudo) por **duas roles** com finalidades distintas, e fechando a rede do
PostgreSQL em loopback. Mantém compatibilidade com os binários ELF legados.

## Filosofia das roles — diferença consciente, não descuido

| Role | Postura | Justificativa |
|---|---|---|
| **`gf_game`** | **AMPLO POR NECESSIDADE** | Os binários WorldServer / ZoneServer / LoginServer / MissionServer / GatewayServer / TicketServer são **closed-source** (Linux ELF stripped). Não há como inventariar exatamente quais SELECTs/INSERTs/UPDATEs/DELETEs cada um faz em cada tabela. Recortar privilégio por tabela seria adivinhação que quebra o jogo em runtime. Conservador = `SELECT,INSERT,UPDATE,DELETE` em tudo do schema `public` dos 3 bancos. Continua MUITO melhor que o `postgres` superuser do install original (sem `CREATEDB`, sem `CREATEROLE`, sem `SUPERUSER`, sem permissão pra alterar schema). |
| **`gf_panel`** | **MÍNIMO POR AUDITORIA** | O painel está em `web/` — código aberto, auditável. Mapeei cada SELECT/INSERT/UPDATE/DELETE chamado nos arquivos PHP e dei só o conjunto exato. Resultado: SELECT em 6 tabelas, INSERT em 4, UPDATE em 5, DELETE em 1 (`gf_ls.accounts` — necessário para o rollback cross-DB do `create_account`). Adicionar uma feature nova ao painel = adicionar GRANT explícito. Isso é uma feature, não um obstáculo. |

### Inventário do `gf_panel` (auditoria em `web/`)

| Banco | Tabela / Sequence | Privilégios | Caminho |
|---|---|---|---|
| gf_ls | `accounts` | S, I, U, D | `lib/accounts.php` (create + rollback), `public/admin/*` |
| gf_ls | `gm_tool_accounts` | S, I, U | `public/admin/gm.php` (upsert) |
| gf_ls | `panel_admins` | S, I, U | `lib/auth.php`, `bin/create-admin.php` |
| gf_ls | `worlds` | **S** | reservado para status futuro (online_user) |
| gf_ls | `account_id_seq_mvp` | USAGE, SELECT, UPDATE | `lib/accounts.php` (nextval) |
| gf_ls | `panel_admins_id_seq` | USAGE, SELECT, UPDATE | serial autouso |
| gf_ms | `tb_user` | S, I, U | create, gold (+AP), GM (byauthority) |
| gf_gs | `player_characters` | S, U | characters, gm, change (rename) |
| gf_gs | `serverstatus` | **S** | reservado para status futuro (ext_address, timers) |

`worlds` e `serverstatus` são `SELECT`-only e inócuos — adicionei para liberar
evolução do painel sem novo deploy de hardening.

## DECISÃO: pg_hba usa `md5`, não `scram-sha-256`

Os binários do GameServer são da era **~2006/2008** — anteriores ao SCRAM
(introduzido no PostgreSQL 10, em 2017). O libpq embarcado fala **apenas md5**.
Tentar `scram-sha-256` no `pg_hba.conf` da faixa 127.0.0.1/32 quebra o login do
jogo, mesmo que o role conheça SCRAM.

Como mitigação: como a conexão é **puramente loopback** (`listen_addresses =
'localhost'`, append idempotente em `postgresql.conf`), o ganho prático de SCRAM
sobre MD5 fica reduzido a zero — não há vetor de captura de hash na rede.

Para que a auth md5 funcione, o `01-roles.sql` também faz
`SET password_encryption = 'md5'` antes do `CREATE/ALTER ROLE`. Sem isso, o role
nasceria com hash SCRAM e o pg_hba md5 falharia.

## `ALTER DEFAULT PRIVILEGES FOR ROLE postgres`

Todos os arquivos `02-grants-*.sql` usam:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO gf_game;
```

O `FOR ROLE postgres` é essencial: nossas migrações de schema (e o `\i` dos
dumps de backup) rodam como `postgres` (peer local). Sem esse `FOR ROLE`, o
default só se aplicaria a tabelas criadas pelo role que **executou** o ALTER —
o que cobriria um caso bem mais estreito. Com `FOR ROLE postgres`, qualquer
tabela criada por updates futuros do server file (ou por restores de backup)
já entra com GRANT correto, e o jogo não quebra silenciosamente quando uma
tabela nova aparece.

## Conteúdo

```
ops/hardening/
├── README.md                   # este arquivo
├── env.example                 # GF_GAME_DB_PASSWORD, GF_PANEL_DB_PASSWORD
├── 01-roles.sql                # CREATE/ALTER ROLE com SET password_encryption='md5'
├── 02-grants-gf_gs.sql         # REVOKE PUBLIC; GRANTs
├── 02-grants-gf_ls.sql         # idem
├── 02-grants-gf_ms.sql         # idem
├── 03-pg-localhost.sh          # listen=localhost + pg_hba md5; .bak.gf-ops + .bak.<ts>
├── 04-update-consumers.sh      # setup.ini + config.local.php (com PRE-FLIGHT)
├── run-hardening.sh            # orquestrador (default: 01-03; --apply-config para 04)
└── rollback.sh                 # restaura .bak.<ts>; --restore-pg; --retire-gf-app
```

## Arquivos do servidor com credencial (atualizados pelo 04)

| Arquivo | Campos tocados | Vira |
|---|---|---|
| `/var/www/gf-panel/config.local.php` | `db.user`, `db.password` | `gf_panel` + senha do env |
| `/root/gf_server/setup.ini` | `GameDBPassword`, `AccountDBPW`, `GameDBUser`, `AccountDBUser` | `gf_game` + senha do env |
| `/root/gf_server/GatewayServer/setup.ini` | `AccountDBPW`, `AccountDBUser` | `gf_game` + senha do env |

`/etc/gf-server/exporter.env` (postgres_exporter) **não** é tocado — já usa role
`gf_exporter` isolada com `pg_monitor`.

## Operação

```bash
# 0) Preparar segredo. Adicione GF_GAME_DB_PASSWORD e GF_PANEL_DB_PASSWORD a
#    /etc/gf-server/env (template: ops/hardening/env.example). Use senhas DIFERENTES.

# 1) Roles + grants + listen/hba (NÃO toca setup.ini ainda)
sudo bash ops/hardening/run-hardening.sh

# 2) Janela de manutenção:
sudo systemctl stop gf.target
sudo systemctl restart postgresql              # toma efeito o listen_addresses
sudo bash ops/hardening/run-hardening.sh --apply-config   # faz pre-flight + reescreve configs
sudo systemctl start gf.target
journalctl -u gf-login -n 80

# 3) Depois de N dias estável, retirar a role ponte:
sudo bash ops/hardening/rollback.sh --retire-gf-app
```

## Rollback (cada nível)

| Cenário | Comando |
|---|---|
| Apliquei configs novas e o jogo não sobe | `sudo bash ops/hardening/rollback.sh` (restaura .bak.<ts> mais recente do setup.ini e config.local.php). Restart gf.target. |
| Endureci pg_hba/listen e algo quebrou | `sudo bash ops/hardening/rollback.sh --restore-pg`. Restart postgresql. |
| Quero remover gf_app definitivamente | `sudo bash ops/hardening/rollback.sh --retire-gf-app` (interativo). |
| Quero remover gf_game/gf_panel também | Manualmente: `sudo -u postgres psql -c 'DROP OWNED BY gf_game; DROP ROLE gf_game;'` (e idem panel). Não há flag — operação rara e perigosa demais. |

Os backups têm timestamp (`.bak.<ts>`) — múltiplas execuções não sobrescrevem
o backup anterior. Existe também um backup nominal (`.bak.gf-ops`) tirado na
primeira execução de `03-pg-localhost.sh` para o `--restore-pg`.

## Idempotência (provas)

- `01-roles.sql`: `IF NOT EXISTS ... CREATE ELSE ALTER` para cada role.
- `02-grants-*.sql`: `GRANT` é aditivo; `REVOKE FROM PUBLIC` é safe re-rodar.
- `03-pg-localhost.sh`: marcador `# gf-ops: hardened ...` evita duplicar bloco
  no postgresql.conf e no pg_hba.conf; `sed` defensivo remove regras antigas.
- `04-update-consumers.sh`: pre-flight aborta antes de tocar arquivo se as
  roles não conectam.

## Validação rápida

```bash
# Roles e privilégios
sudo -u postgres psql -c '\du gf_game'
sudo -u postgres psql -c '\du gf_panel'

# Auth funciona
PGPASSWORD="$GF_GAME_DB_PASSWORD"  psql -h 127.0.0.1 -U gf_game  -d gf_gs -c 'SELECT 1'
PGPASSWORD="$GF_PANEL_DB_PASSWORD" psql -h 127.0.0.1 -U gf_panel -d gf_ls -c 'SELECT 1'

# gf_panel NÃO consegue escrever onde não deve
PGPASSWORD="$GF_PANEL_DB_PASSWORD" psql -h 127.0.0.1 -U gf_panel -d gf_gs \
  -c 'INSERT INTO bags(id,player_id) VALUES (-1,-1)' 2>&1 | grep -i 'permission denied'

# pg_hba endurecido
sudo grep -E '^(listen_addresses|host)' /etc/postgresql/13/main/postgresql.conf \
                                       /etc/postgresql/13/main/pg_hba.conf
```
