#!/usr/bin/env bash
# preflight.sh — checagens ANTES da migração. Não toca nada; só verifica.
#
# Uso:  sudo bash preflight.sh <bundle.tar.zst>
# Sai 0 = pronto para migrar. Sai != 0 = corrige o que faltar.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root

BUNDLE="${1:-}"
[[ -n "$BUNDLE" && -f "$BUNDLE" ]] || die "uso: $0 <bundle.tar.zst gerado por ops/backup>"

# 1) Env mínimo.
[[ -r /etc/gf-server/env ]] || die "/etc/gf-server/env ausente"
mode=$(stat -c '%a' /etc/gf-server/env)
[[ "$mode" == "600" ]] || die "/etc/gf-server/env deve ser 0600 (atual: $mode)"
# shellcheck disable=SC1091
set -a; source /etc/gf-server/env; set +a
: "${GF_GAME_DB_PASSWORD:?GF_GAME_DB_PASSWORD ausente}"
: "${GF_PANEL_DB_PASSWORD:?GF_PANEL_DB_PASSWORD ausente}"
: "${GF_SERVER_HOST_IP:?GF_SERVER_HOST_IP ausente (novo IP do destino)}"

# 2) gf.target não pode estar ativo (migração restaura DBs).
if systemctl is-active --quiet gf.target 2>/dev/null; then
  die "gf.target ATIVO. Pare antes: sudo systemctl stop gf.target"
fi

# 3) Server file presente.
SERVER_ROOT="${GF_SERVER_ROOT:-/root/gf_server}"
[[ -d "$SERVER_ROOT" ]] || die "$SERVER_ROOT ausente (server file deve estar aqui)"
for b in TicketServer/TicketServer GatewayServer/GatewayServer \
         LoginServer/LoginServer MissionServer/MissionServer \
         WorldServer/WorldServer ZoneServer/ZoneServer; do
  [[ -f "${SERVER_ROOT}/${b}" ]] || die "binário ausente: ${SERVER_ROOT}/${b}"
done

# 4) Bundle: existe + extrai sem erro + tem o que esperamos.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
log "verificando bundle $BUNDLE"
tar -xf "$BUNDLE" -C "$WORK"
# Bundle pode vir com 1 diretório raiz ou conteúdo direto. Encontra o diretório
# que contém os 3 .dump.
DUMPDIR=$(find "$WORK" -maxdepth 3 -name 'gf_gs.dump' -printf '%h\n' | head -n1)
[[ -n "$DUMPDIR" ]] || die "bundle não contém gf_gs.dump"
for f in gf_gs.dump gf_ls.dump gf_ms.dump SHA256SUMS manifest.json; do
  [[ -f "${DUMPDIR}/${f}" ]] || die "bundle não contém ${f}"
done
( cd "$DUMPDIR" && sha256sum -c SHA256SUMS )

# 5) Espaço em disco (chute conservador: 5x o bundle).
need_mb=$(( $(stat -c '%s' "$BUNDLE") / 1024 / 1024 * 5 + 256 ))
free_mb=$(df --output=avail /var/lib/postgresql | tail -n1)
free_mb=$(( free_mb / 1024 ))
(( free_mb >= need_mb )) || die "pouco espaço em /var/lib/postgresql: $free_mb MB livre, $need_mb MB necessários"

# 6) IP novo é válido e não-loopback (patch binário recusaria).
IFS=. read -r a b c d <<< "$GF_SERVER_HOST_IP"
for o in "$a" "$b" "$c" "$d"; do
  [[ "$o" =~ ^[0-9]+$ ]] && (( o <= 255 )) || die "GF_SERVER_HOST_IP inválido"
done
[[ "$a" != "127" ]] || die "GF_SERVER_HOST_IP é loopback — cliente externo nunca alcança"

log "PRE-FLIGHT OK. Pronto para migrar:"
log "  bundle:      $BUNDLE"
log "  destino IP:  $GF_SERVER_HOST_IP"
log "  server file: $SERVER_ROOT"
