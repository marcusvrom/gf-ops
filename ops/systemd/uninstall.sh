#!/usr/bin/env bash
# Remove as units do gf-ops de /etc/systemd/system/. Para os serviços antes de remover.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Rode como root (sudo $0)" >&2
  exit 1
fi

UNITS=(
  gf.target
  gf-zone.service
  gf-world.service
  gf-mission.service
  gf-login.service
  gf-gateway.service
  gf-ticket.service
)

systemctl stop gf.target 2>/dev/null || true
for u in "${UNITS[@]}"; do
  systemctl disable "$u" 2>/dev/null || true
  rm -f "/etc/systemd/system/$u"
done
systemctl daemon-reload
echo "removido."
