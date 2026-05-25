#!/usr/bin/env bash
# stage 50 — aplica setup.ini (perms 0600), patch INICIAL com role legada gf_app.
# O hardening (stage 60) reescreve com gf_game depois.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root
log "[50-cfg] delegando para ops/install/05-server-config.sh"
bash "$(dirname "${BASH_SOURCE[0]}")/../../install/05-server-config.sh"
log "[50-cfg] OK"
