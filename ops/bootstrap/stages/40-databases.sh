#!/usr/bin/env bash
# stage 40 — cria gf_gs/gf_ls/gf_ms e carrega schemas. Delegação.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root
log "[40-db] delegando para ops/install/03-databases.sh"
bash "$(dirname "${BASH_SOURCE[0]}")/../../install/03-databases.sh"
log "[40-db] OK"
