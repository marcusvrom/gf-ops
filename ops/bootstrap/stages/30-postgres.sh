#!/usr/bin/env bash
# stage 30 — PostgreSQL 13 (apt.postgresql.org). Delegação para ops/install/02-postgres.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root
log "[30-pg] delegando para ops/install/02-postgres.sh"
bash "$(dirname "${BASH_SOURCE[0]}")/../../install/02-postgres.sh"
log "[30-pg] OK"
