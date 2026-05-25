#!/usr/bin/env bash
# rollback.sh — restaura configs do estado pré-hardening + opção de remover gf_game/gf_panel.
#
# Modo default (sem flag):
#   Restaura o backup MAIS RECENTE (.bak.<ts>) de:
#     /var/www/gf-panel/config.local.php
#     /root/gf_server/setup.ini
#     /root/gf_server/GatewayServer/setup.ini
#   E sugere restart do gf.target. NÃO toca roles nem pg_hba.
#
# Modo --restore-pg:
#   Restaura postgresql.conf e pg_hba.conf a partir do *.bak.gf-ops (nominal,
#   da 1ª vez que 03-pg-localhost rodou). Pede restart do PostgreSQL.
#
# Modo --retire-gf-app:
#   Após confirmar que o jogo está estável nas novas roles, executa:
#     REVOKE ALL ... FROM gf_app; DROP OWNED BY gf_app CASCADE; DROP ROLE gf_app;
#   Pede confirmação interativa.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root

MODE="config"
for arg in "$@"; do
  case "$arg" in
    --restore-pg)     MODE="restore-pg" ;;
    --retire-gf-app)  MODE="retire-gf-app" ;;
    *) die "uso: $0 [--restore-pg|--retire-gf-app]" ;;
  esac
done

restore_latest_bak() {
  local file="$1"
  local bak
  bak=$(ls -1t "${file}.bak."* 2>/dev/null | head -n1 || true)
  if [[ -z "$bak" ]]; then
    warn "nenhum backup encontrado para $file — pulando"
    return
  fi
  log "restaurando $file <- $bak"
  cp -a "$file" "${file}.before-rollback.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  cp -a "$bak" "$file"
}

case "$MODE" in
  config)
    log "restaurando configs (.bak.<ts> mais recente)"
    restore_latest_bak /var/www/gf-panel/config.local.php
    restore_latest_bak /root/gf_server/setup.ini
    restore_latest_bak /root/gf_server/GatewayServer/setup.ini
    cat <<'INFO'

Configs restauradas. Para o jogo voltar à credencial antiga:
  sudo systemctl restart gf.target
  journalctl -u gf-login -n 80

Painel: relê config automaticamente; nenhum restart necessário.
INFO
    ;;

  restore-pg)
    PG_VERSION="${PG_VERSION:-13}"
    PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
    for f in postgresql.conf pg_hba.conf; do
      src="${PG_CONF_DIR}/${f}.bak.gf-ops"
      dst="${PG_CONF_DIR}/${f}"
      [[ -f "$src" ]] || die "backup nominal não encontrado: $src"
      log "restaurando $dst <- $src"
      cp -a "$dst" "${dst}.before-rollback.$(date +%Y%m%d-%H%M%S)"
      cp -a "$src" "$dst"
    done
    cat <<'INFO'

PostgreSQL configs restaurados ao estado pré-hardening.
Reload aplica pg_hba; restart é necessário se listen_addresses mudou:
  sudo systemctl restart postgresql
INFO
    ;;

  retire-gf-app)
    log "retiring gf_app — operação irreversível"
    if ! confirm "confirma DROP ROLE gf_app? (jogo precisa estar em gf_game há tempo suficiente p/ confiar)"; then
      die "abortado"
    fi
    sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='gf_app') THEN
    PERFORM 1;
  ELSE
    RAISE NOTICE 'gf_app não existe — nada a fazer';
    RETURN;
  END IF;
END $$;
SQL
    # DROP OWNED + REASSIGN: precisa ser por banco. Conectamos a cada um.
    for db in gf_gs gf_ls gf_ms postgres; do
      sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$db" -c \
        "REASSIGN OWNED BY gf_app TO postgres; DROP OWNED BY gf_app;" 2>/dev/null || true
    done
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DROP ROLE IF EXISTS gf_app;"
    log "OK — gf_app removido."
    ;;
esac
