#!/usr/bin/env bash
# Instala prometheus-node-exporter (apt) e habilita o textfile collector.
# Roda independente do gf.target. Listening em :9100.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root

log "instalando prometheus-node-exporter"
DEBIAN_FRONTEND=noninteractive apt-get install -y prometheus-node-exporter

# Textfile collector: arquivos *.prom em /var/lib/node_exporter/textfile_collector
# viram métricas. Usamos pra publicar o probe das portas do gf (ver probe/).
TEXTFILE_DIR=/var/lib/node_exporter/textfile_collector
install -d -m 0755 -o root -g root "$TEXTFILE_DIR"
# node_exporter da Ubuntu roda como 'prometheus' — precisa ler o diretório.
chown root:prometheus "$TEXTFILE_DIR" 2>/dev/null || true

# Habilita a flag --collector.textfile.directory via drop-in (não mexe na unit upstream).
DROPIN=/etc/systemd/system/prometheus-node-exporter.service.d
install -d -m 0755 "$DROPIN"
cat > "${DROPIN}/10-gf-textfile.conf" <<EOF
[Service]
# gf-ops: ativa o textfile collector e fixa o diretório.
ExecStart=
ExecStart=/usr/bin/prometheus-node-exporter --collector.textfile.directory=${TEXTFILE_DIR}
EOF

systemctl daemon-reload
systemctl enable --now prometheus-node-exporter
log "OK — node_exporter em :9100. Textfile: ${TEXTFILE_DIR}"
ss -ltn '( sport = :9100 )' || true
