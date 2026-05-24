#!/usr/bin/env bash
# Aplica config nos setup.ini do servidor.
#
# Limitações herdadas (não dá pra resolver sem mexer nos binários):
#   - Os binários ELF lêem setup.ini em texto — a senha do DB FICA em disco.
#     Mitigação: chmod 0600 + chown root:root nos arquivos de config, dir 0750.
#
# Diferenças do install original:
#   - Sem `sed -i` em texto: usamos um filtro em arquivo temporário e movemos
#     com permissões corretas em uma operação atômica.
#   - GameDBUser/AccountDBUser passam a apontar para 'gf_app' (não 'postgres').
#   - Permissões 0600 root:root nos setup.ini.
#   - Sem mexer no /var/www/html/config.php do painel legado (use o painel
#     reescrito em web/, deploy via 06-web.sh).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
load_env

WORLD_INI="${GF_SERVER_ROOT}/setup.ini"
GATEWAY_INI="${GF_SERVER_ROOT}/GatewayServer/setup.ini"

[[ -f "$WORLD_INI" ]]   || die "não encontrado: $WORLD_INI"
[[ -f "$GATEWAY_INI" ]] || die "não encontrado: $GATEWAY_INI"

# Aplica substituições em um tmp e move atomicamente, preservando perms 0600.
# $1: arquivo destino  $2..: pares 'CHAVE=VALOR' (regex ancorado no início da linha,
# tolerante a espaços antes/depois do '=').
apply_ini() {
  local file="$1"; shift
  local tmp; tmp=$(mktemp)
  cp -a "$file" "$tmp"
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    # Escape para sed (replacement side): &, \, /, e a newline.
    local val_esc; val_esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$tmp"; then
      sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${val_esc}|" "$tmp"
    else
      # Não cria chave nova silenciosamente — falha pra evidenciar surpresa de schema.
      die "chave '${key}' não existe em ${file} — confirme antes de criar"
    fi
  done
  install -m 0600 -o root -g root "$tmp" "$file"
  rm -f "$tmp"
  log "atualizado: $file (0600 root:root)"
}

log "ajustando $WORLD_INI"
apply_ini "$WORLD_INI" \
  "GameDBPassword=${GF_DB_PASSWORD}" \
  "AccountDBPW=${GF_DB_PASSWORD}" \
  "GameDBUser=${GF_DB_USER}" \
  "AccountDBUser=${GF_DB_USER}"

log "ajustando $GATEWAY_INI"
apply_ini "$GATEWAY_INI" \
  "AccountDBPW=${GF_DB_PASSWORD}" \
  "AccountDBUser=${GF_DB_USER}"

# Permissão do diretório também — sem chmod 777!
log "ajustando perms de ${GF_SERVER_ROOT}"
chown -R root:root "${GF_SERVER_ROOT}"
chmod 0750 "${GF_SERVER_ROOT}"
# Subdiretórios: dir 0750, arquivos 0640, binários executáveis 0750.
find "${GF_SERVER_ROOT}" -type d -exec chmod 0750 {} +
find "${GF_SERVER_ROOT}" -type f -exec chmod 0640 {} +
for b in TicketServer/TicketServer GatewayServer/GatewayServer \
         LoginServer/LoginServer MissionServer/MissionServer \
         WorldServer/WorldServer ZoneServer/ZoneServer; do
  [[ -f "${GF_SERVER_ROOT}/${b}" ]] && chmod 0750 "${GF_SERVER_ROOT}/${b}"
done
# setup.ini's têm que voltar para 0600 (find acima derrubou para 0640).
chmod 0600 "$WORLD_INI" "$GATEWAY_INI"

log "OK — config do servidor aplicada. Sem chmod 777 em nenhum lugar."
