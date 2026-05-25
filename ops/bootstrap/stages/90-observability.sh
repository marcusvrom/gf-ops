#!/usr/bin/env bash
# stage 90 — observabilidade (OPCIONAL). Pulado por default.
#
# Por que opcional: o gf-server roda sem isto. Em VM de smoke test você não
# quer baixar postgres_exporter, etc. Em produção, rode manualmente:
#   sudo bash ops/observability/install.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root
if [[ "${GF_BOOTSTRAP_OBSERVABILITY:-0}" != "1" ]]; then
  log "[90-obs] pulado (GF_BOOTSTRAP_OBSERVABILITY != 1)"
  exit 0
fi
log "[90-obs] delegando para ops/observability/install.sh"
bash "$(dirname "${BASH_SOURCE[0]}")/../../observability/install.sh"
log "[90-obs] OK"
