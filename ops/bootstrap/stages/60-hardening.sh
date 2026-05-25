#!/usr/bin/env bash
# stage 60 — duas roles dedicadas + pg_hba + reescreve setup.ini / config.local.php.
#
# Roda run-hardening.sh com --apply-config. Em VM virgem isso é seguro porque
# o gf.target ainda não está rodando — não há janela de manutenção a respeitar.
# Em servidor existente, prefira rodar os stages 60 isoladamente, fora do
# bootstrap, em janela controlada (ver ops/hardening/README.md).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root
load_env

: "${GF_GAME_DB_PASSWORD:?defina em /etc/gf-server/env (ver ops/hardening/env.example)}"
: "${GF_PANEL_DB_PASSWORD:?defina em /etc/gf-server/env (ver ops/hardening/env.example)}"

if systemctl is-active --quiet gf.target 2>/dev/null; then
  warn "gf.target está ATIVO — bootstrap em servidor com jogo de pé."
  warn "Pulando 60-hardening; rode manualmente em janela de manutenção:"
  warn "  sudo bash ops/hardening/run-hardening.sh                # roles+grants+hba"
  warn "  sudo systemctl stop gf.target && sudo systemctl restart postgresql"
  warn "  sudo bash ops/hardening/run-hardening.sh --apply-config # reescreve configs"
  warn "  sudo systemctl start gf.target"
  exit 0
fi

log "[60-hard] gf.target inativo — aplicando hardening completo (com --apply-config)"
bash "$(dirname "${BASH_SOURCE[0]}")/../../hardening/run-hardening.sh" --apply-config
log "[60-hard] OK"
