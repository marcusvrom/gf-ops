# web/ — Painel reescrito (PHP + PDO)

Substituição do painel original (`docs/php-reference/`). Mesmas funcionalidades,
sem os defeitos: **SQLi**, **senha em texto plano**, **race de ID**, **páginas admin sem
auth**, **bug `gm_tool_account` singular**.

## O que está incluído

| Arquivo | Papel | Acesso |
|---|---|---|
| `public/index.php` | Registro de conta (atômico, MD5, invariante id==idnum) | público |
| `public/status.php` | Status das portas + contagens | público |
| `public/login.php` / `logout.php` | Auth do painel | público |
| `public/admin/characters.php` | Lista contas e personagens | **admin** |
| `public/admin/gold.php` | Adiciona AP com `SELECT FOR UPDATE` e teto | **admin** |
| `public/admin/gm.php` | Promove/remove GM nos 3 lugares corretos | **admin** |
| `public/admin/change.php` | Renomeia personagem com lock + validação | **admin** |
| `lib/accounts.php` | `create_account()` — espelha o `create_account.sh` | — |
| `migrations/001_account_id_seq_mvp.sql` | Sequence p/ id atômico em `gf_ls` | — |
| `migrations/002_panel_admins.sql` | Tabela de admins do painel (bcrypt) | — |
| `bin/create-admin.php` | CLI p/ criar/atualizar admin | — |

## Decisões e trade-offs

### Senhas: duas camadas separadas
- **Jogo (legado, MD5):** `accounts.password`, `tb_user.password`, `tb_user.pwd`.
  Não dá pra mexer — o LoginServer ESPERA MD5 (CLAUDE.md §6 invariante #2).
  Trocar pra bcrypt **quebra o login**.
- **Painel (novo, bcrypt):** `panel_admins.password_hash`.
  Auth do painel é desacoplada do login do jogo. O hash bcrypt do admin nunca toca
  o servidor de jogo. É a única forma sã de não vazar acesso operacional num panel
  que (a) é exposto em rede e (b) controla GM/AP.

### Atomicidade na criação de conta
- ID via `nextval('account_id_seq_mvp')` em `gf_ls` (não `MAX(id)+1`).
  Mata a race condition do painel original.
- INSERT em `gf_ls.accounts` dentro de transação; se INSERT em `gf_ms.tb_user`
  falhar, `ROLLBACK` no gf_ls. Não é XA (PostgreSQL aceitaria 2PC, mas é exagero
  pro MVP) — é "saga manual" com rollback dirigido, o que é suficiente porque a
  única falha plausível em gf_ms é unique violation ou disco cheio, ambas
  detectáveis antes do commit do gf_ls.
- Verificação final `id==idnum==newId` antes de retornar OK. Se quebrar aqui,
  alguém escreveu por fora — falha explícita em vez de silenciosa.

### Mesma sequence usada pelo `create_account.sh`
Os dois caminhos (CLI e painel) emitem ids do mesmo `account_id_seq_mvp`.
Não há como os dois colidirem mesmo rodando em paralelo. A migration cria a
sequence inicializada acima do `MAX(id)` atual — então a transição do MAX+1
para sequence é segura.

### `gold.php` com `SELECT ... FOR UPDATE`
Dois admins clicando ao mesmo tempo no mesmo `mid` somariam em cima da mesma
leitura. `FOR UPDATE` serializa. O teto de 99999 também é re-checado server-side
(o `max` do `<input>` não basta).

### `gm.php` aplica em 3 lugares — bug corrigido
- `gf_gs.player_characters.privilege` para **TODOS os chars** da conta (e não só
  o que casou o nome — o original deixava chars da mesma conta com privilégios
  inconsistentes).
- `gf_ls.gm_tool_accounts` (PLURAL — o original tinha bug com singular no UPDATE).
- `gf_ms.tb_user.byauthority`.
Upsert manual (SELECT + INSERT/UPDATE) — `ON CONFLICT` precisaria de `UNIQUE(id)`
explícito que pode não existir; manter compatível com schema legado.

### Página de listagem (characters.php) é admin-only
Listar todos os usernames e personagens é information disclosure — útil pra
operação, não pra rede aberta. Saiu de público para `/admin/`.

### CSRF, sessão, escape
- Todos os POST verificam token CSRF.
- `session_regenerate_id` no login. Cookie `HttpOnly`, `SameSite=Lax`, opcional `Secure`.
- Idle timeout configurável.
- Toda saída passa por `h()` (htmlspecialchars com `ENT_QUOTES`).
- `display_errors=0` + `log_errors=1` — não vaza stack trace pro cliente.

### O que NÃO está aqui (escopo)
- Não há rate limit no `/index.php` nem no `/login.php`. fica para item 5
  do backlog (observabilidade + fail2ban) ou WAF na frente.
- Não há recuperação de senha. Admin reseta com CLI; jogador, ainda nada
  (mesma situação do painel original).
- Não há paginação em `characters.php`. Cabe quando passar de algumas centenas
  de contas — não é problema do MVP.

## Setup

```bash
# 1) Migrations (uma vez)
psql -h <host> -U postgres -f web/migrations/001_account_id_seq_mvp.sql
psql -h <host> -U postgres -f web/migrations/002_panel_admins.sql

# 2) Config
cp web/config.example.php web/config.local.php
# editar: db.password, server.host, GF_COOKIE_SECURE em HTTPS, etc.

# 3) Primeiro admin
cd web && php bin/create-admin.php seu_login 'senha-forte-aqui'
```

## Apache vhost (mínimo)

```apache
<VirtualHost *:80>
  ServerName gf.example.local
  DocumentRoot /var/www/gf-panel/public

  <Directory /var/www/gf-panel/public>
    AllowOverride None
    Require all granted
    DirectoryIndex index.php
  </Directory>

  # Os diretórios lib/, migrations/, bin/, config.local.php NÃO ficam acessíveis
  # via web — não estão sob DocumentRoot.
</VirtualHost>
```

Note: deploy é `rsync web/ /var/www/gf-panel/` (mantendo a estrutura inteira).
**DocumentRoot aponta para `public/`** — só ele é exposto.

## Convivência com o painel antigo

Enquanto o servidor estiver isolado em LAN, dá pra rodar os dois lado a lado.
Antes de qualquer exposição pública: desativar o `/var/www/html/*.php` antigo
e apontar o vhost só para `public/` daqui.

## Verificação rápida pós-deploy

- GET `/` carrega o form de registro, status responde (`status.php`).
- POST registro com username de 4 chars cria conta e o id == idnum:
  ```sql
  SELECT id   FROM gf_ls.accounts  WHERE username='teste1';
  SELECT idnum FROM gf_ms.tb_user  WHERE mid='teste1';
  -- devem bater
  ```
- POST registro duplicado responde com erro, sem 500.
- `/admin/gold.php` redireciona pra `/login.php` quando sem sessão.
- POST sem token CSRF responde 400.
