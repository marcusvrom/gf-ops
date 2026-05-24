#!/usr/bin/env bash
# Sonda TCP das portas críticas do gf-server. Publica métricas via textfile
# collector do node_exporter (uma escrita atômica em /var/lib/node_exporter/...).
#
# Rodado pelo gf-port-probe.timer a cada 30s. Independente do gf.target:
# se o servidor cair, esta sonda fica em pé e a métrica vira 0 — é exatamente
# o sinal que monitoração precisa.
set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
OUT="${TEXTFILE_DIR}/gf_ports.prom"
HOST="${GF_PROBE_HOST:-127.0.0.1}"

# Mapeamento das portas (CLAUDE.md §6, achados de runtime).
declare -A PORTS=(
  [ticket]=7777
  [gateway]=5560
  [login]=6543
  [world]=5567
)

probe() {
  local host="$1" port="$2"
  # /dev/tcp do bash — sem dependência externa (nc/ncat).
  if timeout 1 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
    echo 1
  else
    echo 0
  fi
}

tmp=$(mktemp "${TEXTFILE_DIR}/.gf_ports.XXXXXX")
{
  echo "# HELP gf_port_up TCP probe (1=open, 0=closed/timeout) por processo do gf-server."
  echo "# TYPE gf_port_up gauge"
  for service in "${!PORTS[@]}"; do
    port=${PORTS[$service]}
    up=$(probe "$HOST" "$port")
    printf 'gf_port_up{service="%s",port="%s"} %s\n' "$service" "$port" "$up"
  done
  echo "# HELP gf_port_probe_timestamp_seconds Última varredura (epoch)."
  echo "# TYPE gf_port_probe_timestamp_seconds gauge"
  printf 'gf_port_probe_timestamp_seconds %s\n' "$(date +%s)"
} > "$tmp"

# Publicação atômica (node_exporter ignora arquivos não-.prom durante a leitura).
mv "$tmp" "$OUT"
