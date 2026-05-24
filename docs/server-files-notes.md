# Notas de Engenharia Reversa — Server Files (marcusvrom/GameServer)

> Achados confirmados por análise do script `install`, `setup.ini` e estrutura do repo.

## Origem / procedência
- Rede de forks: **SixShoot/gf_server** (raiz) → EddieJr-DigiArts/GameServer_Branch → marcusvrom/GameServer
- Versão de cliente esperada: **A CONFIRMAR** (gate nº 1)

## Stack (confirmada)
- SO testado: Ubuntu Server 22.04 / 20.04
- Banco: PostgreSQL 13 | Web: Apache + PHP (php-pgsql)

## Topologia de processos (diretórios do repo)
LoginServer · GatewayServer · WorldServer · ZoneServer · MissionServer · TicketServer

## Bancos PostgreSQL (3 separados)
| Banco | Papel | Tabela-chave notável |
|-------|-------|----------------------|
| gf_gs | Game Server (mundo, economia, status) | `serverstatus.ext_address` (IP externo) |
| gf_ls | Login Server (contas) | `worlds.ip` (IP do mundo entregue ao client) |
| gf_ms | Mission Server (missões) | — |
- Scripts: `_utils/db/gf_gs.sql`, `gf_ls.sql`, `gf_ms.sql`

## Mecanismo de IP (CRÍTICO) — patch binário
- IP hardcoded nos binários, sobrescrito por `dd` com `conv=notrunc`:
  - WorldServer → offset `0x3EA7A7`
  - ZoneServer  → offset `0x822D47`
- Script zera último octeto (vira endereço de rede), converte p/ hex, escreve nos offsets.
- `.bak` é criado antes do patch.
- Também faz: `UPDATE worlds SET ip='<host_ip>'` (gf_ls) e
  `UPDATE serverstatus SET ext_address='<host_ip>'` (gf_gs).
- Trocar IP = `./install ip` (re-patch). Editar config sozinho NÃO basta.

## Modos do instalador
| Modo | O que faz |
|------|-----------|
| `full` | Instalação completa: purga+reinstala apache/php/pg, cria 3 bancos, patch de IP, copia painel |
| `ip`   | Re-patch do IP nos binários + UPDATE nos bancos |
| `db`   | DROP + recria os 3 bancos do zero |
| `web`  | Instala só o painel (registro/status) em /var/www/html |

## config (setup.ini — defaults)
- GameDB=gf_gs, AccountDBName=gf_ls (DBs)
- GameDBUser=postgres (⚠️ superusuário — corrigir)
- Senha = placeholder `db_pwd` substituído por `sed` no install
- MaxCharacterNumber=9, TicketServerPort=7777, BillingGatewayPort=5560

## Painel PHP
- Origem: `_utils/web/*.php` → copiado p/ `/var/www/html/`
- Config: `/var/www/html/config.php` (placeholders `db_pwd` e `host_ip`)
- Páginas: registro, add gold, conta/personagens, add/remove GM, status, troca de nome

## RISCOS DE SEGURANÇA no install (corrigir antes de expor)
- 🔴 `chmod 777 /root -R` (2x)
- 🔴 PostgreSQL aberto: `listen_addresses='*'` + `pg_hba.conf` `0.0.0.0/0 md5`
- 🔴 Servidor usa superusuário `postgres`
- 🟡 Senha em texto plano via sed em múltiplos arquivos
- 🟡 `full` purga pacotes do sistema (destrutivo) → usar VM dedicada

## Como criar conta GM
- Via painel (página add/remove GM). Detalhar mecanismo após primeiro acesso.

---

## Schema descoberto via análise do painel PHP (_utils/web)

### Registro de conta (toca 2 bancos)
- `gf_ls.accounts` → colunas: `id`, `username`, `password` (TEXTO PLANO ⚠️), `realname`
- `gf_ms.tb_user`  → colunas: `mid` (=username), `password`, `pwd`, `pvalues` (moeda premium/AP), `byauthority` (nível GM)

### Personagens
- `gf_gs.player_characters` → `account_id`, `given_name` (nome do char), `privilege` (5=GM, 0=normal)

### Privilégio de GM (escrita em 3 lugares)
- `gf_gs.player_characters.privilege` = 5
- `gf_ls.gm_tool_accounts` (id, account_name, password, privilege) — NB: bug no código usa `gm_tool_account` singular no UPDATE
- `gf_ms.tb_user.byauthority` = 5

### Moeda premium (AP)
- `gf_ms.tb_user.pvalues` — gold.php soma com teto 99999

### Portas (de config.php)
- login_port=6543, gateway_port=5560, ticket_port=7777

## VEREDITO sobre o painel PHP (decisão registrada)
- **MVP local (VM isolada):** APROVEITAR como está. Funciona, destrava o smoke test.
- **Antes de expor publicamente:** REESCREVER/BLINDAR obrigatoriamente. Motivos:
  - 🔴 SQL Injection em 100% dos endpoints (concatenação de $_POST direto na query)
  - 🔴 Senhas em texto plano (sem hash)
  - 🔴 Geração de ID por COUNT(*)+loop → race condition em registros concorrentes
  - 🟡 gm.php e gold.php SEM autenticação (qualquer um vira GM / dá AP infinito)
  - 🟡 bug gm_tool_account (singular) vs gm_tool_accounts (plural)
- Stack da reescrita: aberta (só fala com PostgreSQL). PHP moderno + PDO/prepared
  statements é o menor atrito; decidir na hora.

---

## Mapa completo de bancos (via análise dos 3 .sql)

Totais: **gf_gs = 113 tabelas | gf_ls = 17 | gf_ms = 14**

### gf_ls (Login Server) — contas e mundos
- `accounts` (10 col): id, username, password (texto plano), realname, worldserver,
  use_charpassword, charpassword, state, char_max_num, win_os_bit
- `worlds` (9 col): id, name, **ip**, port, online_user, maxnum_user, state, version, show_order
- `gm_tool_accounts` (4 col): id, account_name, password, privilege
- itemmall, lottery, fortune_bag, exchange_pin/rule, item_receipt/receivable, etc.

### gf_ms (Mission/Member Server) — autenticação e moeda premium
- `tb_user` (17 col): mid, password, pwd, idnum, **byauthority** (nível GM), **pvalues** (AP/cash),
  firstlogindate, billingrule, status, regdate, lastlogindate, memberid, clientip, bonus, char_id
- game_log, gmtool_log, web_itemmall_log, oauth2_* (logs e billing)

### gf_gs (Game Server) — o coração (113 tabelas)
- `player_characters` (121 col!): id, given_name, x/y/z/face_dir (posição), class_id, race_id,
  level, exp (bigint), **gold** (bigint), **crystal**, account_id, privilege, family_id,
  rebirth_*, aa_point, arena_point, reputation, bank_duedate_*, etc.
- `bags` (47 col): inventário — id, item_id, durability, player_id, loc, strengthen, embedded_*,
  awake_*, rune_combo_* (item rico em atributos = alvo de dupe)
- `auction` (55 col): leilão — seller_id, auction_price (bigint), item_id, due_date (VETOR DE DUPE)
- `gold_log` (13 col): agregador diário — date, increase, decrease, range1..range10 (faixas de gold)
- `vip`, `vip_card`: status VIP (silver_time/golden_time)
- inventory1/2, equipment1/2, storage1/2, mailitem, family*, isle* (casas), elf* (pets)
- serverstatus (14 col): ext_address (IP externo), portas, timers de eventos

### Pontos-chave para ANTI-DUPE (economia)
- Fontes de valor: `player_characters.gold`, `player_characters.crystal`, `tb_user.pvalues`,
  itens em `bags`/`storage`/`auction`.
- `gold_log` já existe → base para detectar inflação anômala.
- Vetores clássicos: leilão (auction), trade, mail com item, storage compartilhado (account_shared).
- Itens têm identidade rica (strengthen, embedded, awake) → dupe de item raro é alto impacto.

---

## Script `server` (launcher) — análise

Comandos: start | stop | restart | status | backup | restore | clear

### Ordem de boot CONFIRMADA (com sleep 2 entre cada)
1. TicketServer  (./TicketServer -p 7777)
2. GatewayServer
3. LoginServer
4. MissionServer
5. WorldServer
6. ZoneServer
- Todos iniciam em background com `&>/dev/null` (⚠️ ZERO log — ver workaround no runbook).
- Faz `chmod 777 *` em cada pasta antes de iniciar (⚠️ mesma praga do install).

### Backup/restore JÁ EXISTEM (boa notícia)
- `./server backup`  → pg_dump -Fp dos 3 bancos em /root/gf_server/backup/backup_<timestamp>/
- `./server restore <pasta>` → DROP + recria + psql -f dos 3 bancos
- ⚠️ Ambos fazem `chmod -R 777 /root` ao final. Backup é LOCAL (mesma máquina) — sem off-site.

### `./server clear` — PERIGOSO
- Zera /var/log/syslog, wtmp, maillog, messages, secure. Apaga logs do SISTEMA, não do jogo.
- NÃO usar. Comportamento típico de script que veio "sujo". Remover na versão hardened.

### stop usa killall -9 (SIGKILL)
- Mata os processos abruptamente. Risco de corromper estado não-salvo sob carga.
- Em produção: preferir parada graciosa + checkpoint de save.

---

## GATE Nº 1 RESOLVIDO — Versão do cliente (investigação concluída)

### Versão-alvo identificada
- String no banco (worlds.version): **006.058.64.64**
- Binário ZoneServer monta dinamicamente: **`006.%s.64.64`** + label `ZoneServer Version:`
- Conclusão: **o número de BUILD que precisa casar é o `058`**. Segmentos 006 e 64.64 são fixos.
- schema_version: gf_ls=812300000 | gf_gs=2006081400 (sufixo tipo data 2006/08/14 — linhagem antiga)
- login_version no banco = "Unknown_Version(Login)" (login não força label de versão)

### Engine / protocolo (assinatura de compatibilidade)
- Namespace do engine: **lapis** (símbolos N5lapis...)
- Comandos de rede: CNC_CL_Client* (Client→Login), CNC_CZ_Client* (Client→Zone), CNC_G_*
- Um cliente só é compatível se falar exatamente esse conjunto de comandos.
- Binários: ELF 32-bit, statically linked, stripped (Linux 2.6.32+).

### DESCOBERTA CRÍTICA — bypass de versão na LAN
LoginServer contém:
  "try to login to WorldServer with unmatch version.(W:[..]/C:[..])"
  "ignored verification, version and world state bcz connect from LAN"
=> O servidor RECUSA login se versão do cliente != versão do mundo,
   MAS IGNORA a checagem se a conexão vem da LAN.
=> Para o MVP em VM isolada/LAN: a verificação de versão é contornada.
   Isso reduz drasticamente o risco do "gate nº 1" para o teste local.
   (Em produção/IP público a checagem VOLTA a valer — cliente DEVE ser build 058.)

### Onde obter o cliente correto (ordem de prioridade)
1. A thread de fórum original onde a linhagem SixShoot/gf_server foi publicada
   (RaGEZONE / elitepvpers) — o cliente "que veio junto" é o garantido.
2. Cliente de build 006.058 da mesma região dessa linhagem.
3. Qualquer cliente: testar via LAN primeiro (bypass acima) para validar o loop,
   depois confirmar paridade exata antes de expor publicamente.

### Como confirmar a paridade num cliente candidato
- Procurar no cliente a string de versão (006.058 / 64.64) em arquivos de config/ini ou
  no executável (strings).
- Conferir se os arquivos de dados (mapas/itens) batem com o schema do servidor.
- Teste decisivo: conectar via LAN (bypass) e ver se entra no mundo sem desync;
  depois testar com checagem de versão ativa.

---

## GATE Nº 1 — FECHADO ✅ (cliente obtido)

- Cliente obtido: pasta **GF_ES_006.058.64.64** (via thread RaGEZONE da linhagem).
- Confirmação de paridade: nome da pasta = string worlds.version (006.058.64.64) = padrão
  do binário ZoneServer (006.%s.64.64, build 058). Match exato.
- GF_ES = idioma Espanhol apenas na UI; NÃO afeta protocolo (engine lapis, comandos CNC_*).
  PT-BR seria localização posterior dos textos em data/ — não bloqueia o MVP.
- Estrutura do cliente confirmada completa: data, map, item, monster, npc, char, effect,
  elf, font, bgm, Movies, Opening, Microsoft.VC80 (runtime VC++2005, coerente com a era).
- AÇÃO: backup local imediato do cliente (links de fórum/MEGA somem).
- No install: escolher o IP da interface da VM (cliente está em outra máquina/host),
  não 127.0.0.1 — é o que o patch binário grava e o que o cliente precisa alcançar.

---

## ACHADOS DE EXECUÇÃO REAL (VM Hyper-V Ubuntu 22.04) — Fases 1 e 2 CONCLUÍDAS ✅

> Fonte: relatório de execução (docs/relatorio-mvp-execucao.pdf). Servidores sobem e login
> funciona. Estes achados só apareceram em runtime — não eram detectáveis por análise estática.

### 1. INVARIANTE CRÍTICA DE DADOS (a causa-raiz do "Erro de Sistema")
**gf_ls.accounts.id DEVE SER IGUAL a gf_ms.tb_user.idnum** (mesma conta).
- Se divergir: LoginServer aceita a senha mas retorna `WRONG account id` → "Erro de Sistema" no client.
- É uma PK logicamente compartilhada entre 2 bancos distintos → sem FK possível →
  integridade tem que ser garantida na ESCRITA, atomicamente.
- Mapeamento completo de conta (todas obrigatórias):
  - gf_ls.accounts.id      = gf_ms.tb_user.idnum
  - gf_ls.accounts.username = gf_ms.tb_user.mid
  - gf_ls.accounts.password = gf_ms.tb_user.password = tb_user.pwd = **MD5** da senha

### 2. SENHA É MD5 (não texto plano, não bcrypt)
- O servidor ESPERA md5(senha) em accounts.password e tb_user.password/pwd.
- Painel original gravava texto plano → login REJEITAVA. Correção: md5() no cadastro.
- Implicação: não dá p/ trocar p/ bcrypt sem mexer no protocolo do servidor (legado).
  Hardening de senha fica limitado ao que o servidor aceita.

### 3. BINÁRIOS 32-BIT LEGADOS — pré-requisitos de SO (obrigatório)
- Erro `loadlocale.c:130` + abort → forçar `LC_ALL=C LANG=C LANGUAGE=C`.
- Precisa de libs i386: `dpkg --add-architecture i386` + libc6:i386 libstdc++6:i386
  libgcc-s1:i386 zlib1g:i386.
- Crash SIGSEGV em resolução de nome (/var/run/nscd/socket) → instalar e iniciar **nscd**;
  garantir `hosts: files dns` em /etc/nsswitch.conf.

### 4. ORDEM DE BOOT — agora com dependência causal provada
- LoginServer dá ECONNREFUSED em 127.0.0.1:7777 se TicketServer não subiu antes.
- Ordem (dura, não cosmética): Ticket(7777) → Gateway(5560) → Login(6543) →
  Mission → World(5567, no IP da VM) → Zone.

### 5. Ruídos NÃO-bloqueantes (não confundir com erro de login)
- `race_rank_old does not exist` → feature de ranking/corrida; backlog de conteúdo.
- `S_RootCmds.ini is fail` → arquivo opcional ausente; não afeta login.

### Portas confirmadas em runtime
Ticket 7777 | Gateway 5560 | Login 6543 | World 5567 (no IP da VM) | Zone (interno)

### Observabilidade: o relatório criou start_debug.sh/stop_debug.sh
- Substituem o `./server` original: sobem em ordem, com LOG POR PROCESSO (resolve o &>/dev/null),
  validam portas, e disparam strace no LoginServer se ele não subir. Adotar como baseline.

---

## Solução de criação de conta (scripts/setup/create_account.sh)

O relatório corrige a invariante com MAX(id)+1 — funciona, mas mantém RACE CONDITION
(dois cadastros simultâneos leem o mesmo MAX). O script create_account.sh resolve com:
- ID atômico via SEQUENCE dedicada (account_id_seq_mvp), não MAX(id)+1.
- Insert nos 2 bancos com o MESMO id; rollback do gf_ls se o gf_ms falhar.
- MD5 da senha (confirmado: md5('123456')=e10adc3949ba59abbe56e057f20f883e).
- Verificação final da invariante id==idnum antes de retornar OK.
- Flag opcional 'gm' eleva byauthority=5.
Uso: ./create_account.sh <user> <senha> [gm]

NOTA p/ reescrita do painel: a mesma lógica (sequence + transação cross-DB + md5) deve
ir pro PHP, com prepared statements. A invariante id==idnum é requisito funcional, não opcional.
