# CLAUDE.md — Grand Fantasia Private Server (Projeto MVP)

> Este arquivo é lido pelo Claude Code no início de cada sessão. Mantenha-o
> atualizado: é a fonte de verdade do estado do projeto e das convenções.
> Regra de ouro: se algo mudou no mundo real (versão, IP, estrutura), atualize aqui ANTES de pedir código.

---

## 1. O que é este projeto

Servidor privado de **Grand Fantasia** (MMORPG da X-Legend). Objetivo de longo prazo:
comunidade de 500+ players. **Fase atual: MVP local** — provar que o loop jogável
fecha numa única máquina antes de pensar em escala.

**Definição de pronto do MVP — ✅ JÁ ATINGIDA (24/05/2026):**
> Um jogador registra conta, loga, entra no mundo, anda, mata mob, upa e troca de mapa,
> com os dados persistindo no PostgreSQL local.

MVP validado: personagem subiu a nv8, deslogou e relogou com progresso persistido.
A viabilidade técnica está PROVADA. A fase atual agora é **hardening e automação**
(systemd, painel seguro, observabilidade) rumo a um servidor exposível.

---

## 2. Natureza do projeto (LEIA antes de propor código)

> **STACK REAL (confirmada por análise do repo marcusvrom/GameServer):**
> **Linux (Ubuntu Server 22.04/20.04) + PostgreSQL + PHP/Apache.**
> NÃO é Windows, NÃO é MSSQL, NÃO é .NET. Qualquer instrução assumindo Windows/MSSQL
> está OBSOLETA. Origem da rede de forks: SixShoot/gf_server → EddieJr-DigiArts → marcusvrom.

Este projeto tem DUAS camadas com naturezas opostas:

### Camada A — Os binários do servidor (NÃO desenvolvemos)
- WorldServer, ZoneServer, LoginServer, GatewayServer, MissionServer, TicketServer são
  **binários Linux ELF fechados**. NÃO existe source. Não tente "implementar/corrigir" lógica deles.
- **O IP do servidor está HARDCODED dentro dos binários** e é aplicado via PATCH HEX pelo
  script `install`, não por config. Offsets conhecidos (deste build):
  - `WorldServer` → offset `0x3EA7A7`
  - `ZoneServer`  → offset `0x822D47`
  - O script zera o último octeto do IP (vira endereço de rede), converte para bytes hex e
    escreve via `dd ... seek=0x<offset> conv=notrunc`. Guarda `.bak` antes. Por isso trocar de
    IP exige re-rodar `./install ip` — não basta editar arquivo.
- Trabalho aqui = operação, configuração (`setup.ini`) e patch de IP. Cliente: **GF_ES_006.058.64.64** (✅ confirmado).

### Camada B — Tooling ao redor (AQUI o Claude Code trabalha)
- Painel web: **JÁ EXISTE em PHP** (`_utils/web/*.php`, copiado p/ `/var/www/html/`). Decisão pendente:
  aproveitar no MVP vs reescrever. Default recomendado: aproveitar agora, reescrever depois se preciso.
- Tooling NOVO a construir: load test, observabilidade, auditoria de economia, automação de ops,
  e **versão hardened do `install`** (ver §6 armadilhas de segurança).

---

## 3. Stack e convenções

**Stack do SERVIDOR (fixa, definida pelo server file — não há escolha):**
- SO: **Ubuntu Server 22.04** (ou 20.04). Banco: **PostgreSQL 13**. Web: **Apache + PHP** (php-pgsql).
- Três bancos separados: `gf_gs` (game/economia/status), `gf_ls` (login/contas/tabela `worlds`),
  `gf_ms` (mission). Scripts em `_utils/db/gf_gs.sql`, `gf_ls.sql`, `gf_ms.sql`.
- Config do servidor: `setup.ini` (e `GatewayServer/setup.ini`). Senha do DB injetada via `sed`
  no placeholder `db_pwd`. Painel lê `/var/www/html/config.php`.

**Stack do TOOLING NOVO (poliglota por componente; Go EXCLUÍDO):**

| Componente | Tecnologia | Por quê |
|------------|-----------|---------|
| Harness de load test | **Rust + Tokio** | I/O async de baixo overhead p/ centenas de conexões; sem GC jitter na medição; controle fino dos bytes do protocolo |
| Automação de ops / install hardened | **Bash + Ansible** | Nativo no fluxo Linux existente; idempotência via Ansible; sem runtime extra na VM |
| Observabilidade | **node_exporter + postgres_exporter + Prometheus/Grafana** | Padrão de mercado p/ host + PostgreSQL |
| Auditoria de economia | **SQL (PL/pgSQL)** | Roda direto no PostgreSQL; nada a abstrair |
| Painel web | **PHP existente no MVP; reescrever antes de expor** | Funciona p/ smoke test, mas tem SQLi em 100% dos endpoints + senha em texto plano + páginas admin sem auth. Decisão em server-files-notes.md |
| Bot de Discord | a decidir | Sem dependência de banco; decidir quando chegar a hora |

- **Acesso ao PostgreSQL no Rust:** crate `tokio-postgres` (async, nativo).
- **Versionamento:** configs com placeholders (NUNCA a senha real), scripts SQL, runbooks.
- **Estilo Rust:** edição 2021+, `Result`/`?` (sem `unwrap` em prod), `clippy` limpo, Tokio, deps mínimas.
- **Estilo de resposta esperado:** justificativa técnica, trade-offs, foco em produção. Objetivo mas técnico.

---

## 4. Estrutura do repositório

```
gf-mvp/
├── CLAUDE.md                  # este arquivo
├── README.md                  # quickstart humano
├── .gitignore
├── docs/
│   ├── smoke-test.md          # checklist do loop jogável (✅ validado)
│   ├── server-files-notes.md  # engenharia reversa: schema, invariantes, achados de execução
│   ├── INTEGRATION.md         # como gf-ops e GameServer convivem (2 repos)
│   ├── relatorio-mvp-execucao.pdf  # relatório dos achados em runtime
│   ├── sql-reference/         # os 3 dumps .sql (gf_gs/gf_ls/gf_ms)
│   └── php-reference/         # painel PHP original (referência p/ reescrita)
├── config/
│   ├── templates/             # configs com PLACEHOLDERS (versionado)
│   └── local/                 # configs reais com IP/senha (gitignored)
├── scripts/
│   ├── setup/                 # create_account.sh (invariante de ID atômica)
│   └── sql/audit/             # queries de auditoria de economia (gold_log)
├── tools-rs/                  # tooling Rust (workspace Cargo)
│   ├── confcheck/             # valida configs
│   ├── healthcheck/           # checa portas TCP + ping no DB
│   └── loadtest/              # harness de carga async (Tokio)
├── web/                       # painel reescrito (PHP+PDO ou a decidir) — Camada B
├── bot/                       # bot de Discord (a decidir)
└── ops/
    ├── backup/                # backup off-site dos 3 bancos PostgreSQL
    ├── systemd/               # unit files (gf-*.service) — PRÓXIMO passo
    └── compose/               # provisionamento da VM (fase de escala)
```

> Workspace Rust único em `tools-rs/` (um `Cargo.toml` de workspace, crates por binário) —
> compartilha o parser de protocolo entre healthcheck e loadtest. Soluções .NET (`web/`, `bot/`)
> em `.sln` próprias.

---

## 5. Estado atual do MVP (ATUALIZAR a cada sessão)

| Etapa | Status | Notas |
|-------|--------|-------|
| Server files obtidos (fork marcusvrom) | ✅ feito | Origem: SixShoot → EddieJr → marcusvrom |
| Paridade de versão client/server | ✅ RESOLVIDO | Cliente **GF_ES_006.058.64.64** obtido (RaGEZONE). Bate com worlds.version e binário. ES=só idioma da UI. |
| Backup local dos arquivos do repo | ⬜ TODO | Repo pode sumir (451) |
| VM Ubuntu 22.04 (Hyper-V) provisionada | ✅ feito | Funcional. Requer libs i386 + locale C + nscd |
| Stack instalada e processos sobem | ✅ feito | Ordem causal: Ticket→Gateway→Login→Mission→World→Zone |
| 3 bancos criados (gf_gs/gf_ls/gf_ms) | ✅ feito | |
| Login funcional (cliente conecta) | ✅ feito | Após corrigir MD5 + sincronia de IDs |
| Painel PHP acessível (registro/status) | ✅ analisado | Funciona; aproveitar no MVP. Schema mapeado em notes. Reescrever antes de expor (SQLi) |
| Cliente conecta (GF_ES 006.058) | ✅ feito | Via LAN; World em IP da VM:5567 |
| Smoke test do loop completo | ✅ COMPLETO | Loop validado: criar→mundo→quest→up nv8→relogar→persistiu |
| Conta GM + comandos básicos | ✅ feito | TesteADM funcional in-game |
| Versão hardened do install | ⬜ TODO | Antes de qualquer exposição pública |

Legenda: ⬜ TODO · 🟡 em progresso · ✅ feito · 🔴 bloqueado

---

## 6. Armadilhas conhecidas (aprendizado acumulado)

### INVARIANTES CRÍTICAS (descobertas em execução real — NUNCA violar)
- 🔑 **gf_ls.accounts.id == gf_ms.tb_user.idnum** para a mesma conta. Divergência →
  LoginServer retorna `WRONG account id` → "Erro de Sistema" no client. É PK compartilhada
  entre 2 bancos sem FK → garantir na escrita, atomicamente.
- 🔑 **Senha = md5(senha)** em accounts.password E tb_user.password/pwd. Servidor legado
  espera MD5; texto plano OU bcrypt quebram o login.
- 🔑 **Pré-req de SO:** locale C (LC_ALL/LANG/LANGUAGE=C) + libs i386 + nscd ativo.
  Sem isso os binários 32-bit nem sobem.
- 🔑 **Ordem de boot é causal:** TicketServer(7777) ANTES do LoginServer, senão ECONNREFUSED.

### Mecânica do servidor
- **IP é patch binário, não config.** O IP do servidor está hardcoded no `WorldServer`/`ZoneServer`
  (offsets `0x3EA7A7` / `0x822D47`). Trocar de IP = re-rodar `./install ip`. Editar `setup.ini`
  sozinho NÃO muda o IP que o cliente recebe. O script também atualiza `worlds.ip` (gf_ls) e
  `serverstatus.ext_address` (gf_gs) no banco.
- **Mismatch de versão:** server files e cliente DEVEM ser da mesma versão/região.
- **Ordem de boot:** ver invariante causal acima (Ticket→Gateway→Login→Mission→World→Zone).

### Segurança — RISCOS GRAVES no `install` original (corrigir antes de QUALQUER exposição)
- 🔴 **`chmod 777 /root -R`** — torna todo o /root acessível a qualquer usuário. Aparece 2x. Remover.
- 🔴 **PostgreSQL exposto à internet** — o script seta `listen_addresses='*'` e `pg_hba.conf` para
  `0.0.0.0/0 md5`. Banco aberto ao mundo, só com senha. Restringir a localhost/rede interna.
- 🔴 **Servidor conecta como superusuário `postgres`** — zero isolamento. Criar role dedicada com
  privilégios mínimos por banco.
- 🟡 **Senha em texto plano** propagada via `sed` para `setup.ini`, `GatewayServer/setup.ini`,
  `config.php`. Mover para secret/variável de ambiente.
- 🟡 **`./install full` purga pacotes do sistema** (`apt purge apache2/php/postgresql`) — destrutivo
  se a VM já tiver esses serviços. Por isso: VM dedicada e descartável.

> Regra: rodar o `install` original SOMENTE em VM isolada/descartável, nunca no host compartilhado
> de 56 cores. Inspecionar > validar > só então confiar. Versão hardened é trabalho da Camada B.

### Operação
- **Repos públicos instáveis** (DMCA/451): backup local imediato dos arquivos. O fork pode sumir.

---

## 7. Restrições e limites (importante)

- **Legal:** sem fins lucrativos, sem pay-to-win. Não usar a marca comercialmente.
- **Escopo do MVP:** NÃO é escala. Não otimizar para 500 players agora. Rodar numa máquina.
- **Não inventar:** se não souber a estrutura exata de um server file, peça para inspecionar
  o arquivo real em vez de assumir. Documentar o achado em `docs/server-files-notes.md`.

---

## 8. Backlog priorizado (a fila de trabalho do Claude Code)

MVP validado. Próximas tarefas em ordem de prioridade:

1. **systemd units** (`ops/systemd/`) — substituir o boot manual por 6 services
   (gf-ticket → gf-gateway → gf-login → gf-mission → gf-world → gf-zone) com
   `After=`/`Requires=` na ordem causal, `Environment=LC_ALL=C LANG=C LANGUAGE=C`,
   dependência de `nscd` e `postgresql`, log por processo (resolve o `&>/dev/null`).
   Mais um `gf.target` que orquestra todos. Base: docs/relatorio-mvp-execucao.pdf §6.
2. **Painel reescrito** (`web/`) — PHP+PDO com prepared statements; embutir a lógica
   atômica do `scripts/setup/create_account.sh` (sequence + transação cross-DB + md5 +
   invariante id==idnum); auth nas páginas admin (gm/gold). Mata SQLi + race + dessync.
3. **Hardening do install** — role PostgreSQL dedicada (sem superusuário), PG só em
   localhost, sem `chmod 777`, segredo fora do texto plano.
4. **Backup off-site** (`ops/backup/`) — estender o `./server backup` (pg_dump) com cópia
   para fora da VM + teste de restore. Remover o `chmod -R 777` do script original.
5. **Observabilidade** — node_exporter + postgres_exporter + Grafana; uptime na porta de login.
6. **Auditoria de economia** (`scripts/sql/audit/`) — consumir `gold_log` p/ detectar inflação.

> Antes de começar QUALQUER tarefa: ler este CLAUDE.md inteiro e docs/server-files-notes.md.
> As invariantes da §6 são inegociáveis — código que as viole quebra o login.
