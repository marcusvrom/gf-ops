# ops/bootstrap — Ubuntu Server 22.04 virgem → gf-server pronto pra subir

Materializa em script tudo que historicamente foi manual. O objetivo é simples:
**reprovisionar do zero, com 1 comando**, e provar que nenhuma etapa ficou só
na documentação. Idempotente — re-rodar não quebra nada.

## Cruzamento "achado → stage"

Cada item de `docs/server-files-notes.md` e `CLAUDE.md §6` que era pré-requisito
de SO ou de aplicação está mapeado para um stage executável:

| Achado (docs/server-files-notes.md) | Stage | Como vira código |
|---|---|---|
| Locale C obrigatório (`loadlocale.c` abort) | **10** | `update-locale LANG=C LC_ALL=C` + grava `/etc/default/locale` (persistente) + `Environment=` nas units (já no ops/systemd) |
| Libs i386 (libc6, libstdc++6, libgcc-s1, zlib1g) | **10** | `dpkg --add-architecture i386` + `apt install ...:i386` |
| nscd ativo + `hosts: files dns` | **10** | `apt install nscd` + `systemctl enable --now` + sed defensivo em `nsswitch.conf` |
| `php-pgsql` no painel | **20** | apt |
| **`php-mbstring`** (regressão: registro quebra sem ele) | **20** | apt — antes era manual, agora é código |
| PostgreSQL 13 + repo apt.postgresql.org | **30** | delega para `ops/install/02-postgres.sh` |
| 3 bancos com OWNER + sequence MVP | **40** | delega para `ops/install/03-databases.sh` |
| Patch binário de IP (offsets 0x3EA7A7 / 0x822D47) | (não bootstrap) | feito pelo `ops/migrate/` quando há dados a restaurar; bootstrap puro deixa o IP do install inicial |
| setup.ini com perms 0600 root:root | **50** | delega para `ops/install/05-server-config.sh` |
| Duas roles dedicadas (gf_game/gf_panel) + pg_hba md5 + listen=localhost | **60** | delega para `ops/hardening/run-hardening.sh --apply-config` |
| Painel reescrito + vhost + migrations + admin via CLI | **70** | delega para `ops/install/06-web.sh` |
| Ordem causal Ticket→Gateway→Login→Mission→World→Zone | **80** | delega para `ops/systemd/install.sh` (Requires/After) |
| Observabilidade (gauges, sonda TCP) | **90** | opcional, gated por `GF_BOOTSTRAP_OBSERVABILITY=1` |
| Invariante #1 (id == idnum) | (não bootstrap) | invariante de **aplicação**: garantida por `web/lib/accounts.php` (sequence + saga manual) + `scripts/setup/create_account.sh`. Auditável via `scripts/sql/audit/`. |
| Invariante #2 (senha MD5) | (não bootstrap) | invariante de **aplicação**: tem que estar no código quem cria conta. O bootstrap não toca senhas do jogo. |
| Invariante #4 (ordem de boot causal) | **80** (via systemd) | Requires=/After= encadeados nas units |

**Itens novos que ESTE bootstrap fecha (lacunas que existiam):**
1. `php-mbstring` — antes só na cabeça de quem instalou; agora `stage 20`.
2. Locale C persistente em `/etc/default/locale` — antes só via `Environment=`
   das units; agora também para shells interativos e diagnóstico.
3. `nsswitch.conf` com sed defensivo — antes manual; agora `stage 10`.
4. Encadeamento garantido `install → hardening → web → systemd`, com pre-checks
   e mensagens claras.

## Pré-requisitos (no servidor, antes do `bootstrap.sh`)

1. **VM Ubuntu Server 22.04** (também roda em 20.04). Recomendado: snapshot antes.
2. **Server file em `/root/gf_server/`** — binários do GameServer (este repo NÃO
   distribui). Sem isso, o stage 50 aborta com mensagem.
3. **Dumps `.sql` em `/root/gf_server/_utils/db/`** (gf_gs.sql, gf_ls.sql,
   gf_ms.sql) — vem com o server file.
4. **`/etc/gf-server/env` preenchido** (modo 0600 root:root):
   ```bash
   sudo mkdir -p /etc/gf-server
   sudo cp ops/install/env.example   /etc/gf-server/env
   sudo cat ops/hardening/env.example >> /etc/gf-server/env
   sudo chmod 600 /etc/gf-server/env
   sudo $EDITOR /etc/gf-server/env
   ```
   Mínimos para um bootstrap completo:
   - `GF_DB_PASSWORD` (legado, role ponte gf_app)
   - `GF_GAME_DB_PASSWORD`, `GF_PANEL_DB_PASSWORD` (hardening, roles novas)
   - `GF_SERVER_HOST_IP` (patch de IP)

## Operação

```bash
# Roda tudo, com confirmação por stage (bootstrap.sh não pergunta; chama scripts
# que perguntam quando faz sentido):
sudo bash ops/bootstrap/bootstrap.sh

# Retomar a partir do stage X (útil quando um falhou no meio):
sudo bash ops/bootstrap/bootstrap.sh --from 60

# Só um subset (ex.: ressincronizar hardening + redeploy do painel):
sudo bash ops/bootstrap/bootstrap.sh --only 60,70

# Com observabilidade:
sudo GF_BOOTSTRAP_OBSERVABILITY=1 bash ops/bootstrap/bootstrap.sh
```

## Como testar numa VM descartável (ensaio da migração real)

1. Provisionar Ubuntu Server 22.04 (qcow2/vhdx/etc). Snapshot zero.
2. Copiar o repo gf-ops para `/root/gf-ops/`.
3. Copiar o server file para `/root/gf_server/` (e os `.sql` para `_utils/db/`).
4. Criar `/etc/gf-server/env` (ver acima).
5. Rodar:
   ```bash
   sudo bash /root/gf-ops/ops/bootstrap/bootstrap.sh
   sudo systemctl start gf.target
   cd /var/www/gf-panel && sudo php bin/create-admin.php admin1 'senha-forte'
   ```
6. Validar:
   - `systemctl is-active gf.target` → `active`
   - `ss -ltn | grep -E ':(7777|5560|6543|5567)\b'` → 4 portas escutando
   - `curl -s http://<IP-VM>/status.php` → mostra "Online" nos 3 processos
   - Conectar cliente `GF_ES_006.058.64.64` em LAN, criar conta pelo painel,
     logar, criar personagem, andar.
7. Se tudo OK, restaurar snapshot zero e repetir — o teste prova que o bootstrap
   é **realmente reproduzível**, não dependente do estado anterior.

## Idempotência

Re-rodar `bootstrap.sh` (mesmo `--from 10`) numa VM já provisionada **não pode
quebrar nada**. Os stages 10/20 são `apt install` (já instalado = no-op). 30 e
40 verificam `IF NOT EXISTS`. 50/60 têm marcadores e `.bak.<ts>`. 70 tem
`rsync --delete`. 80 reinstala units (`install -m 0644`).
