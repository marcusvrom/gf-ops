#!/usr/bin/env bash
# stage 80 — instala as units do gf.target. NÃO inicia.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root
log "[80-systemd] delegando para ops/systemd/install.sh"
bash "$(dirname "${BASH_SOURCE[0]}")/../../systemd/install.sh"
log "[80-systemd] OK — gf.target instalado e habilitado (sem start)."
log "             para iniciar: sudo systemctl start gf.target"
