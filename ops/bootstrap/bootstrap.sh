#!/usr/bin/env bash
# bootstrap.sh — provisiona uma Ubuntu Server 22.04 virgem para rodar o gf-server.
#
# Reproduz, em CÓDIGO IDEMPOTENTE, todas as etapas que historicamente foram
# manuais. Mapeamento "achado de runtime -> stage" no docs/runtime-requirements.md.
#
# Uso:
#   sudo bash ops/bootstrap/bootstrap.sh                 # roda 10..80 (90 opt)
#   sudo bash ops/bootstrap/bootstrap.sh --from 30       # retoma a partir de 30
#   sudo bash ops/bootstrap/bootstrap.sh --to 50         # para depois de 50
#   sudo bash ops/bootstrap/bootstrap.sh --only 10,40    # roda só os listados
#
# Pré-requisitos no /etc/gf-server/env (ver ops/install/env.example +
# ops/hardening/env.example):
#   GF_GAME_DB_PASSWORD, GF_PANEL_DB_PASSWORD (obrigatórias para o stage 60)
#   GF_SERVER_HOST_IP (obrigatório para o stage 50: patch de IP)
#   GF_SERVER_ROOT (default /root/gf_server) — server file deve estar aqui
#   GF_SQL_DIR (default $GF_SERVER_ROOT/_utils/db) — dumps .sql do schema
#
# Pré-requisito FÍSICO: o server file (binários do GameServer) deve estar em
# GF_SERVER_ROOT ANTES do stage 50. Este repo NÃO distribui os binários.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../install/lib.sh"
require_root

ALL_STAGES=(10 20 30 40 50 60 70 80 90)
FROM=10; TO=90; ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)  FROM="$2"; shift 2 ;;
    --to)    TO="$2";   shift 2 ;;
    --only)  ONLY="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,30p' "$0"; exit 0 ;;
    *) die "flag desconhecida: $1" ;;
  esac
done

# Pré-check do env (cedo, para falhar antes de instalar nada).
if [[ ! -r "$GF_ENV_FILE" ]]; then
  die "$GF_ENV_FILE não existe. Crie a partir de:
  ops/install/env.example   (GF_DB_PASSWORD, GF_SERVER_HOST_IP, ...)
  ops/hardening/env.example (GF_GAME_DB_PASSWORD, GF_PANEL_DB_PASSWORD)
  Modo: 0600 root:root."
fi

# Decide quais stages rodar.
if [[ -n "$ONLY" ]]; then
  IFS=',' read -ra TO_RUN <<< "$ONLY"
else
  TO_RUN=()
  for s in "${ALL_STAGES[@]}"; do
    (( s >= FROM )) && (( s <= TO )) && TO_RUN+=("$s")
  done
fi

log "stages a rodar: ${TO_RUN[*]}"

# Verifica server file antes de chamar 50 (depende de /root/gf_server existir).
for s in "${TO_RUN[@]}"; do
  if [[ "$s" == "50" ]]; then
    : "${GF_SERVER_ROOT:=/root/gf_server}"
    [[ -d "$GF_SERVER_ROOT" ]] || die "stage 50 requer $GF_SERVER_ROOT (server file não está lá).
Copie os binários do GameServer antes de rodar este stage."
  fi
done

for s in "${TO_RUN[@]}"; do
  script="${HERE}/stages/${s}-"*.sh
  # Expande glob.
  set -- $script
  [[ -f "$1" ]] || die "stage $s não encontrado em ${HERE}/stages/"
  log "=========================================================="
  log " executando stage $s ($(basename "$1"))"
  log "=========================================================="
  bash "$1"
done

log "BOOTSTRAP CONCLUÍDO. Próximos passos:"
log "  sudo systemctl start gf.target"
log "  cd /var/www/gf-panel && sudo php bin/create-admin.php <user> <senha>"
log "  Verificar status:"
log "    systemctl status gf.target"
log "    journalctl -u gf-login -f"
log "    ss -ltn | grep -E ':(7777|5560|6543|5567)\b'"
