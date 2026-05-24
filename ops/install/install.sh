#!/usr/bin/env bash
# Orquestrador. Roda os 6 passos em ordem, com confirmação por etapa.
# Cada script é idempotente — pode reexecutar.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"
require_root

[[ -r "$GF_ENV_FILE" ]] || {
  err "$GF_ENV_FILE não existe."
  err "  sudo mkdir -p /etc/gf-server"
  err "  sudo cp ${HERE}/env.example ${GF_ENV_FILE}"
  err "  sudo chmod 600 ${GF_ENV_FILE} && sudo chown root:root ${GF_ENV_FILE}"
  err "  sudo \$EDITOR ${GF_ENV_FILE}"
  exit 1
}

STEPS=(
  "01-os-prereqs.sh"
  "02-postgres.sh"
  "03-databases.sh"
  "04-ip-patch.sh"
  "05-server-config.sh"
  "06-web.sh"
)

for s in "${STEPS[@]}"; do
  echo "==========================================================="
  echo " etapa: ${s}"
  echo "==========================================================="
  if confirm "rodar ${s}?"; then
    bash "${HERE}/${s}"
  else
    warn "pulado: ${s}"
  fi
done

log "TUDO PRONTO. Próximos passos:"
log "  - subir o servidor:   systemctl start gf.target  (ver ops/systemd/)"
log "  - criar admin painel: cd /var/www/gf-panel && php bin/create-admin.php <user> <senha>"
log "  - testar status:      http://\$(hostname -I | awk '{print \$1}')/status.php"
