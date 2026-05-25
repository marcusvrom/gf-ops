#!/usr/bin/env bash
# 04-update-consumers.sh — troca a credencial em TODOS os arquivos que falam com o PG.
#
# Lista de arquivos com credencial (inventário do servidor):
#   /var/www/gf-panel/config.local.php          (painel  -> gf_panel)
#   /root/gf_server/setup.ini                   (jogo    -> gf_game)
#   /root/gf_server/GatewayServer/setup.ini     (jogo    -> gf_game)
#
# Política de segurança:
#   - PRE-FLIGHT: testa psql -U gf_game e gf_panel ANTES de tocar qualquer arquivo.
#     Se algum falhar, aborta. (Sem isso, a primeira ida ao banco mata o jogo.)
#   - Backup .bak.<ts> de cada arquivo modificado.
#   - Escrita atômica (tmp + rename) preservando perms 0600 root:root no setup.ini
#     e 0640 root:www-data no config.local.php.
#   - NÃO reinicia gf.target nem apache. Imprime o comando para o operador.
#
# Rollback: ./rollback.sh restaura os .bak.<ts> mais recentes.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root
load_env

: "${GF_GAME_DB_PASSWORD:?defina em /etc/gf-server/env}"
: "${GF_PANEL_DB_PASSWORD:?defina em /etc/gf-server/env}"

WORLD_INI="${GF_SERVER_ROOT}/setup.ini"
GATEWAY_INI="${GF_SERVER_ROOT}/GatewayServer/setup.ini"
PANEL_CFG="/var/www/gf-panel/config.local.php"

# --- 1) Pre-flight: roles realmente respondem ---
log "pre-flight: testando conexão como gf_game e gf_panel"
PGPASSWORD="$GF_GAME_DB_PASSWORD" psql -h 127.0.0.1 -U gf_game -d gf_gs -tAc 'SELECT 1' >/dev/null \
  || die "gf_game não conecta. Rode 01-roles.sql e os 02-grants-*.sql primeiro."
PGPASSWORD="$GF_PANEL_DB_PASSWORD" psql -h 127.0.0.1 -U gf_panel -d gf_ls -tAc 'SELECT 1' >/dev/null \
  || die "gf_panel não conecta. Rode 01-roles.sql e os 02-grants-*.sql primeiro."

log "pre-flight: testando grants efetivos (smoke test)"
PGPASSWORD="$GF_PANEL_DB_PASSWORD" psql -h 127.0.0.1 -U gf_panel -d gf_ls -tAc \
  "SELECT count(*) FROM accounts" >/dev/null || die "gf_panel sem SELECT em gf_ls.accounts"
PGPASSWORD="$GF_PANEL_DB_PASSWORD" psql -h 127.0.0.1 -U gf_panel -d gf_ms -tAc \
  "SELECT count(*) FROM tb_user" >/dev/null || die "gf_panel sem SELECT em gf_ms.tb_user"
PGPASSWORD="$GF_GAME_DB_PASSWORD" psql -h 127.0.0.1 -U gf_game -d gf_gs -tAc \
  "SELECT count(*) FROM player_characters" >/dev/null || die "gf_game sem SELECT em gf_gs"

TS=$(date +%Y%m%d-%H%M%S)

# Aplica chaves CHAVE=VALOR num ini, atomicamente, preservando perms.
# Falha duro se a chave não existir (não cria silenciosamente — schema-aware).
apply_ini() {
  local file="$1" mode="$2" owner="$3" group="$4"; shift 4
  [[ -f "$file" ]] || die "não encontrado: $file"
  cp -a "$file" "${file}.bak.${TS}"
  local tmp; tmp=$(mktemp)
  cp -a "$file" "$tmp"
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    local val_esc; val_esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$tmp"; then
      sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${val_esc}|" "$tmp"
    else
      rm -f "$tmp"
      die "chave '${key}' não existe em ${file} — confirme antes de criar"
    fi
  done
  install -m "$mode" -o "$owner" -g "$group" "$tmp" "$file"
  rm -f "$tmp"
  log "atualizado: $file (backup: ${file}.bak.${TS})"
}

# --- 2) painel primeiro (a senha velha gf_app fica inerte imediatamente para o painel) ---
if [[ -f "$PANEL_CFG" ]]; then
  log "atualizando $PANEL_CFG"
  cp -a "$PANEL_CFG" "${PANEL_CFG}.bak.${TS}"
  # Regenera o arquivo inteiro: ele tem só keys conhecidas, mais previsível que sed.
  tmp=$(mktemp)
  cat > "$tmp" <<PHP
<?php
return [
    'db' => [
        'host'     => '${GF_DB_HOST:-127.0.0.1}',
        'port'     => '${GF_DB_PORT:-5432}',
        'user'     => 'gf_panel',
        'password' => '${GF_PANEL_DB_PASSWORD}',
    ],
    'server' => [
        'host'         => '${GF_SERVER_HOST_IP}',
        'login_port'   => 6543,
        'gateway_port' => 5560,
        'ticket_port'  => 7777,
    ],
    'session' => [
        'name'            => 'gfpanel',
        'cookie_secure'   => false,
        'cookie_samesite' => 'Lax',
        'idle_timeout'    => 1800,
    ],
    'registration' => [
        'enabled'      => true,
        'min_user_len' => 4,
        'max_user_len' => 20,
        'min_pass_len' => 6,
        'user_regex'   => '/^[A-Za-z0-9_]+\$/',
    ],
];
PHP
  install -m 0640 -o root -g www-data "$tmp" "$PANEL_CFG"
  rm -f "$tmp"
  log "  backup: ${PANEL_CFG}.bak.${TS}"
else
  warn "$PANEL_CFG não existe — pulando painel"
fi

# --- 3) game servers ---
apply_ini "$WORLD_INI" 0600 root root \
  "GameDBPassword=${GF_GAME_DB_PASSWORD}" \
  "AccountDBPW=${GF_GAME_DB_PASSWORD}" \
  "GameDBUser=gf_game" \
  "AccountDBUser=gf_game"

apply_ini "$GATEWAY_INI" 0600 root root \
  "AccountDBPW=${GF_GAME_DB_PASSWORD}" \
  "AccountDBUser=gf_game"

cat <<INFO

NÃO REINICIEI NADA AUTOMATICAMENTE. Para tomar efeito:

  # Painel — Apache pode continuar de pé (PHP relê config a cada request).
  # Já está usando gf_panel a partir desta linha.

  # Jogo — restart obrigatório (binários lêem setup.ini só no boot):
    sudo systemctl restart gf.target

Depois do restart, valide o login pela porta 6543:
    journalctl -u gf-login -n 80
    nc -zv 127.0.0.1 6543

Se algo quebrar:
    sudo bash $(dirname "${BASH_SOURCE[0]}")/rollback.sh

A role gf_app continua viva como ponte. Para removê-la, depois que o jogo
estiver estável:
    sudo bash $(dirname "${BASH_SOURCE[0]}")/rollback.sh --retire-gf-app
INFO

log "OK"
