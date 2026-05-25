#!/usr/bin/env bash
# migrate.sh — orquestrador da migração para servidor novo.
#
# Pressupõe:
#   - VM destino virgem (Ubuntu Server 22.04). Snapshot zero antes.
#   - Server file (binários do GameServer) já em /root/gf_server/.
#   - Bundle do pg_dump produzido pelo ops/backup/backup.sh — passar caminho.
#   - /etc/gf-server/env preenchido (ver ops/bootstrap/README.md).
#
# Etapas (cada uma pode rodar isolada se preciso):
#   1. preflight       — checa env, server file, bundle, espaço, IP
#   2. bootstrap       — provisiona o SO (idempotente; safe em VM já preparada)
#   3. restore         — pg_restore dos 3 dumps + REASSIGN OWNED + setval na sequence
#   4. ip-patch        — dd nos binários (offsets 0x3EA7A7 / 0x822D47) + UPDATE nos bancos
#   5. start           — systemctl start gf.target
#   6. post-validate   — portas TCP, contagens, invariante #1
#
# NÃO executa NADA sem confirmação por etapa (default), a menos que --yes.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../install/lib.sh"
require_root

BUNDLE=""
YES=0
SKIP_BOOTSTRAP=0
SKIP_HARDENING=0
FROM=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)         YES=1; shift ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=1; shift ;;
    --skip-hardening) SKIP_HARDENING=1; shift ;;
    --from)           FROM="$2"; shift 2 ;;
    -h|--help)        sed -n '1,30p' "$0"; exit 0 ;;
    -*)               die "flag desconhecida: $1" ;;
    *)                BUNDLE="$1"; shift ;;
  esac
done
[[ -n "$BUNDLE" ]] || die "uso: $0 <bundle.tar.zst> [--yes] [--skip-bootstrap] [--skip-hardening] [--from N]"

ask() {
  local prompt="$1"
  (( YES )) && return 0
  read -r -p "$prompt [s/N] " ans
  [[ "$ans" =~ ^[sSyY]$ ]]
}

# ETAPA 1 — preflight (sempre)
log "==== ETAPA 1/6 — preflight ===="
bash "${HERE}/preflight.sh" "$BUNDLE"

if (( FROM <= 2 )); then
  log "==== ETAPA 2/6 — bootstrap ===="
  if (( SKIP_BOOTSTRAP )); then
    warn "  --skip-bootstrap: pulado"
  else
    ask "rodar bootstrap (provisiona SO + PG + painel)?" \
      && bash "${HERE}/../bootstrap/bootstrap.sh" \
      || warn "pulado por escolha do operador"
  fi
fi

if (( FROM <= 3 )); then
  log "==== ETAPA 3/6 — restore ===="
  # Extrai bundle para um diretório fixo, restore.sh consome.
  EXTRACT_DIR="/var/backups/gf-server/migrate-$(date +%Y%m%d-%H%M%S)"
  install -d -m 0750 -o root -g root "$EXTRACT_DIR"
  tar -xf "$BUNDLE" -C "$EXTRACT_DIR"
  # Bundle pode ter 1 nível de subdir; resolve.
  RESTORE_DIR=$(find "$EXTRACT_DIR" -maxdepth 3 -name 'gf_gs.dump' -printf '%h\n' | head -n1)
  log "  bundle extraído em: $RESTORE_DIR"
  ask "rodar restore (DROP+CREATE+pg_restore dos 3 bancos)?" \
    && bash "${HERE}/../backup/restore.sh" "$RESTORE_DIR" --yes-i-really-mean-it \
    || warn "pulado por escolha do operador"
fi

if (( FROM <= 4 )); then
  log "==== ETAPA 4/6 — ip patch ===="
  ask "patch hex do IP nos binários (offsets 0x3EA7A7 / 0x822D47) + UPDATE bancos?" \
    && bash "${HERE}/../install/04-ip-patch.sh" \
    || warn "pulado por escolha do operador"
fi

# Hardening (opcional dentro do migrate, pois bootstrap já faz; ainda assim
# permite ressincronizar se o restore trouxe schema com objetos novos que
# precisam de GRANT — ALTER DEFAULT PRIVILEGES cobre mas ressincroniza por
# garantia).
if (( FROM <= 4 )) && (( ! SKIP_HARDENING )); then
  log "==== ETAPA 4.5/6 — ressync grants ===="
  ask "ressincronizar GRANTs (re-roda 02-grants em cada banco)?" \
    && for db in gf_gs gf_ls gf_ms; do
         sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$db" \
           -f "${HERE}/../hardening/02-grants-${db}.sql"
       done \
    || warn "pulado"
fi

if (( FROM <= 5 )); then
  log "==== ETAPA 5/6 — start ===="
  ask "systemctl start gf.target?" \
    && systemctl start gf.target \
    || warn "pulado por escolha do operador"
  sleep 5
fi

if (( FROM <= 6 )); then
  log "==== ETAPA 6/6 — post-validate ===="
  bash "${HERE}/post-validate.sh" "$BUNDLE"
fi

cat <<INFO

MIGRAÇÃO CONCLUÍDA.

Para acompanhar:
  systemctl status gf.target
  journalctl -u 'gf-*.service' -f
  ss -ltn | grep -E ':(7777|5560|6543|5567)\b'

Smoke test do gameplay (em outra máquina, com o client GF_ES_006.058.64.64):
  - Tela de login responde (porta 6543).
  - Conta existente loga (mesma senha — md5 não muda).
  - Personagem volta com nível e posição preservados.

Se algo quebrou:
  - sudo bash ops/hardening/rollback.sh                     (configs)
  - sudo bash ops/hardening/rollback.sh --restore-pg        (pg_hba/listen)
  - sudo bash ops/backup/restore.sh <bundle anterior> --yes-i-really-mean-it
INFO
