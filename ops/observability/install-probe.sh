#!/usr/bin/env bash
# Instala a sonda de portas em /opt/gf-ops/ + units + textfile dir.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/probe" && pwd)"
DST=/opt/gf-ops/ops/observability/probe

install -d -m 0755 -o root -g root "$DST"
install -m 0755 -o root -g root "${SRC}/gf-port-probe.sh" "${DST}/gf-port-probe.sh"

install -d -m 0755 -o root -g root /var/lib/node_exporter/textfile_collector

install -m 0644 "${SRC}/gf-port-probe.service" /etc/systemd/system/
install -m 0644 "${SRC}/gf-port-probe.timer"   /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now gf-port-probe.timer
log "OK — sonda ativa. Próxima execução:"
systemctl list-timers gf-port-probe.timer --no-pager
