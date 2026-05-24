#!/usr/bin/env bash
# Orquestrador da observabilidade. Cada etapa é OPCIONAL e independente do gf.target.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../install/lib.sh"
require_root

STEPS=(
  "install-node-exporter.sh"
  "install-postgres-exporter.sh"
  "install-probe.sh"
)

cat <<MSG
==========================================================================
 Observabilidade — TODOS os componentes são OPCIONAIS.

 O gf-server roda sem nada disso. Estes scripts apenas EXPÕEM métricas em:
   :9100  node_exporter (host + textfile com gf_port_up)
   :9187  postgres_exporter (stats + custom queries gf_*)

 Prometheus e Grafana ficam num HOST SEPARADO — este repo NÃO instala nem
 configura nenhum dos dois. Exemplos em prometheus.example.yml e
 grafana-dashboard.example.json.
==========================================================================
MSG

for s in "${STEPS[@]}"; do
  echo "---"
  if confirm "rodar ${s}?"; then
    bash "${HERE}/${s}"
  else
    warn "pulado: ${s}"
  fi
done

log "OK. Verifique:"
log "  curl -s http://127.0.0.1:9100/metrics | grep -E '^(gf_|node_load1) '"
log "  curl -s http://127.0.0.1:9187/metrics | grep -E '^(pg_up|gf_)'"
