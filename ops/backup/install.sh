#!/usr/bin/env bash
# Instala scripts em /opt/gf-ops/ops/backup/ e habilita gf-backup.timer.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST_BIN="/opt/gf-ops/ops/backup"
DST_LIB="/opt/gf-ops/ops/install"

log "instalando scripts em ${DST_BIN}"
install -d -m 0750 -o root -g root "$DST_BIN" "$DST_LIB"
install -m 0750 -o root -g root \
  "${SRC}/backup.sh" "${SRC}/restore.sh" "${SRC}/verify-restore.sh" "$DST_BIN/"
# lib.sh é compartilhada — copiada de ops/install/ para preservar o source path do script.
install -m 0640 -o root -g root "${SRC}/../install/lib.sh" "$DST_LIB/lib.sh"

log "instalando units"
install -m 0644 "${SRC}/gf-backup.service" /etc/systemd/system/
install -m 0644 "${SRC}/gf-backup.timer"   /etc/systemd/system/

install -d -m 0750 -o root -g root /var/backups/gf-server

systemctl daemon-reload
systemctl enable --now gf-backup.timer
log "OK — timer habilitado. Próxima execução:"
systemctl list-timers gf-backup.timer --no-pager
log "rodar imediatamente: systemctl start gf-backup.service"
