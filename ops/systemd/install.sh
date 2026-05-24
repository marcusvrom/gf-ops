#!/usr/bin/env bash
# Instala as units do gf-ops em /etc/systemd/system/ e habilita o gf.target.
# Idempotente. Não inicia nada — chame `systemctl start gf.target` depois.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Rode como root (sudo $0)" >&2
  exit 1
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="/etc/systemd/system"

UNITS=(
  gf-ticket.service
  gf-gateway.service
  gf-login.service
  gf-mission.service
  gf-world.service
  gf-zone.service
  gf.target
)

# Sanidade: pré-requisitos das invariantes #3 do CLAUDE.md
for pkg_bin in nscd; do
  if ! command -v "$pkg_bin" >/dev/null 2>&1; then
    echo "AVISO: '$pkg_bin' não encontrado no PATH. Instale antes de iniciar gf.target." >&2
  fi
done
if ! systemctl list-unit-files nscd.service >/dev/null 2>&1; then
  echo "AVISO: nscd.service não existe no systemd. As units dependem dele (invariante #3)." >&2
fi
if ! systemctl list-unit-files postgresql.service >/dev/null 2>&1; then
  echo "AVISO: postgresql.service não existe no systemd. As units dependem dele." >&2
fi
if [[ ! -d /root/gf_server ]]; then
  echo "AVISO: /root/gf_server não existe. As units assumem este path (ajuste com 'sed -i').".
fi

for u in "${UNITS[@]}"; do
  install -m 0644 "$SRC/$u" "$DST/$u"
  echo "instalado: $DST/$u"
done

systemctl daemon-reload
systemctl enable gf.target gf-ticket.service gf-gateway.service gf-login.service \
                 gf-mission.service gf-world.service gf-zone.service

cat <<EOF

OK. Para subir agora:
  systemctl start gf.target

Para acompanhar:
  systemctl status gf.target
  journalctl -u gf-login -f
EOF
