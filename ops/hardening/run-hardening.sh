#!/usr/bin/env bash
# Orquestrador do hardening. Cada etapa pode rodar independente; este wrapper
# garante a ORDEM correta:
#   01-roles   : cria gf_game e gf_panel
#   02-grants  : aplica permissões mínimas (revoga PUBLIC, GRANTs por banco)
#   03-pg      : listen=localhost + pg_hba md5
#   04-consum  : SÓ se --apply-config for passado (toca setup.ini do jogo).
#
# Default: roda 01, 02, 03. Faltando --apply-config, 04 é só listado como passo
# manual seguinte. Decisão deliberada: 04 é o ponto onde podemos quebrar o jogo
# se o pre-flight falhar — preferimos que seja explícito.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../install/lib.sh"
require_root
load_env

: "${GF_GAME_DB_PASSWORD:?}"
: "${GF_PANEL_DB_PASSWORD:?}"

APPLY_CONFIG=0
for arg in "$@"; do
  case "$arg" in
    --apply-config) APPLY_CONFIG=1 ;;
    *) die "flag desconhecida: $arg (use: $0 [--apply-config])" ;;
  esac
done

log "etapa 01 — roles"
# Senhas via -v; psql substitui em :'name' como literal seguro.
sudo -u postgres psql -v ON_ERROR_STOP=1 \
  -v game_pwd="${GF_GAME_DB_PASSWORD}" \
  -v panel_pwd="${GF_PANEL_DB_PASSWORD}" \
  -f "${HERE}/01-roles.sql"

log "etapa 02 — grants por banco"
for db in gf_gs gf_ls gf_ms; do
  log "  grants em ${db}"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$db" -f "${HERE}/02-grants-${db}.sql"
done

log "etapa 03 — pg_hba/postgresql.conf (localhost + md5)"
bash "${HERE}/03-pg-localhost.sh"

if (( APPLY_CONFIG )); then
  log "etapa 04 — atualiza setup.ini e config.local.php"
  bash "${HERE}/04-update-consumers.sh"
else
  cat <<NEXT

ROLES CRIADAS, GRANTS APLICADOS, REDE ENDURECIDA.
O setup.ini do jogo e o config.local.php do painel AINDA usam credencial antiga.

Quando estiver pronto para trocar (em janela de manutenção):

  sudo bash ${HERE}/run-hardening.sh --apply-config
  # ele faz pre-flight em gf_game/gf_panel e só toca config se conectar OK

  sudo systemctl restart gf.target
  journalctl -u gf-login -n 80

Antes disso, os 3 binários e o painel continuam conectando como gf_app
(role ponte). Nada quebrou.
NEXT
fi

log "OK"
