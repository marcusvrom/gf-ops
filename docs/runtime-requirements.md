# Runtime Requirements — gf-server

**Lugar único e óbvio** para quem precisar saber "do que o servidor depende
em tempo de execução". Cada item aponta para o stage do `ops/bootstrap/`
que o materializa (e o achado original em `docs/server-files-notes.md`,
quando aplicável).

## TL;DR

```bash
# Tudo é instalado em UM comando, idempotente:
sudo bash ops/bootstrap/bootstrap.sh
```

Detalhe por categoria abaixo.

---

## 1. Sistema operacional

Versão: **Ubuntu Server 22.04 LTS** (compatível com 20.04). Não testado em
distribuições não-Debian.

### 1.1. Locale obrigatório `C`

| O que | Por quê | Quem aplica |
|---|---|---|
| `LANG=C`, `LC_ALL=C`, `LANGUAGE=C` em `/etc/default/locale` | binários ELF abortam com `loadlocale.c:130 abort` sem isso (achado de runtime #3 do notes) | `stage 10` (`ops/bootstrap/stages/10-os.sh`) |
| `Environment=LC_ALL=C LANG=C LANGUAGE=C` em cada `gf-*.service` | mesmo motivo, escopo da unit | `ops/systemd/gf-*.service` |

### 1.2. Arquitetura i386 + libs 32-bit

Os binários do GameServer são ELF 32-bit (statically linked, stripped, Linux 2.6.32+).

| Pacote | Comando | Quem aplica |
|---|---|---|
| `i386` foreign-arch | `dpkg --add-architecture i386` | `stage 10` |
| `libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386` | `apt install` | `stage 10` |

### 1.3. `nscd` ativo + nsswitch

Sem `nscd`, o binário do LoginServer crasha em `getaddrinfo` por causa de
ausência do socket `/var/run/nscd/socket` (achado de runtime #3).

| O que | Quem aplica |
|---|---|
| `nscd` instalado e `systemctl enable --now` | `stage 10` |
| `/etc/nsswitch.conf` com `hosts: files dns` | `stage 10` (sed defensivo) |

---

## 2. PostgreSQL

Versão: **PostgreSQL 13** (do repo oficial `apt.postgresql.org`). Versões mais
novas não foram testadas; o schema é antigo (sufixos `2006081400`).

| Componente | Detalhe | Quem aplica |
|---|---|---|
| `postgresql-13` | apt do repo upstream | `stage 30` |
| `listen_addresses = 'localhost'` | só loopback; ganho de SCRAM zera | `ops/install/02-postgres.sh` + `ops/hardening/03-pg-localhost.sh` |
| `pg_hba.conf` com `host all all 127.0.0.1/32 md5` | binários ELF (~2006) usam libpq pré-SCRAM | `ops/hardening/03-pg-localhost.sh` |
| `password_encryption = 'md5'` ao criar roles | sem isto, o role nasceria SCRAM e a auth md5 falha | `ops/hardening/01-roles.sql` (SET por sessão) |
| Roles `gf_game` (RW completo) e `gf_panel` (mínimo auditado) | privilégio mínimo possível | `ops/hardening/` |
| Bancos `gf_gs`, `gf_ls`, `gf_ms` (template0, UTF8, OWNER gf_app→gf_game) | esquema dividido por escopo | `ops/install/03-databases.sh` |
| Sequence `account_id_seq_mvp` em `gf_ls` | ID atômico para `accounts.id == tb_user.idnum` (invariante #1) | `ops/install/03-databases.sh` |
| Tabela `panel_admins` em `gf_ls` | auth do painel (bcrypt — desacoplada do MD5 do jogo) | `web/migrations/002_panel_admins.sql` (via `ops/install/06-web.sh`) |

---

## 3. Web (painel)

Stack: **Apache + PHP** (mod_php). Sem Composer, sem JS, sem dependências externas.

| Extensão PHP | Por quê | Quem aplica |
|---|---|---|
| `php-pgsql` (PDO_pgsql) | conexão com PostgreSQL via PDO | `stage 20` + `ops/install/06-web.sh` |
| **`php-mbstring`** | `mb_strlen()` em `index.php` e admin pages. **Sem isto, o registro de jogador quebra em runtime** ("Call to undefined function mb_strlen"). Foi a lacuna que motivou este documento. | `stage 20` + `ops/install/06-web.sh` |

Arquivos de configuração do painel:
- `/var/www/gf-panel/config.local.php` (`db.user`, `db.password`) — escrito
  inicialmente pelo `06-web.sh` com `gf_app`; reescrito pelo
  `04-update-consumers.sh` com `gf_panel`.

---

## 4. systemd

Unit files em `ops/systemd/`. Encadeamento causal:
`gf-ticket → gf-gateway → gf-login → gf-mission → gf-world → gf-zone`,
orquestradas por `gf.target`. Sem isso (`./server start` original com `sleep 2`)
o LoginServer dá ECONNREFUSED no TicketServer em VMs lentas.

Dependências sistêmicas declaradas em cada unit:
- `After=network-online.target nscd.service postgresql.service`
- `Requires=nscd.service` (na primeira unit da cadeia)

---

## 5. Aplicação (invariantes que não viram pacote/config)

Estas são invariantes que vivem **no código** — o bootstrap garante o ambiente,
mas o código tem que respeitar:

| Invariante (CLAUDE.md §6) | Onde mora no código |
|---|---|
| `gf_ls.accounts.id == gf_ms.tb_user.idnum` | `web/lib/accounts.php::create_account()` + `scripts/setup/create_account.sh` (ambos usam `account_id_seq_mvp` + verificação final + saga manual cross-DB) |
| Senha = MD5 em `accounts.password`, `tb_user.password`, `tb_user.pwd` | `web/lib/accounts.php` (`md5($passwordRaw)`) + `create_account.sh` |
| Ordem causal de boot | `ops/systemd/gf-*.service` (`Requires=`/`After=`) |
| Pré-req de SO (locale C / i386 / nscd) | `ops/bootstrap/stages/10-os.sh` (este documento) |

---

## 6. Patch binário de IP (não-runtime, mas relevante)

O IP do servidor está **dentro** dos binários WorldServer e ZoneServer:

| Binário | Offset | Aplicado por |
|---|---|---|
| `WorldServer` | `0x3EA7A7` | `ops/install/04-ip-patch.sh` (com `.bak` preservado + audit sha256) |
| `ZoneServer`  | `0x822D47` | idem |

Trocar de IP exige re-rodar o patch + UPDATE nos bancos (`worlds.ip` e
`serverstatus.ext_address`) — feito automaticamente pelo `04-ip-patch.sh`.
O `ops/migrate/` chama no destino.

---

## 7. Opcional (não bloqueante)

| Componente | Para que serve | Como ligar |
|---|---|---|
| `prometheus-node-exporter` | métricas de host + sonda de portas do gf via textfile collector | `ops/observability/install-node-exporter.sh` |
| `postgres_exporter` v0.15 | métricas do PG + custom queries do gf_gs/gf_ls/gf_ms | `ops/observability/install-postgres-exporter.sh` |
| `gf-port-probe.timer` | TCP probe a cada 30s nas 4 portas do gf | `ops/observability/install-probe.sh` |
| `gf-backup.timer` | pg_dump diário + off-site (SSH ou rclone) | `ops/backup/install.sh` |

`gf.target` **não depende** de nenhum destes — todos são standalone.
