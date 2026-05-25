#!/usr/bin/env bash
# stage 70 — deploy do painel reescrito + vhost + migrations.
# Delega para ops/install/06-web.sh (que já roda como gf_panel após o hardening).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root
log "[70-web] delegando para ops/install/06-web.sh"
bash "$(dirname "${BASH_SOURCE[0]}")/../../install/06-web.sh"
log "[70-web] OK"
