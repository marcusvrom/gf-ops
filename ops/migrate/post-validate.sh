#!/usr/bin/env bash
# post-validate.sh — checks PÓS-migração. Não escreve, só observa.
#
# Uso:  sudo bash post-validate.sh <bundle.tar.zst>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root

BUNDLE="${1:-}"
[[ -n "$BUNDLE" && -f "$BUNDLE" ]] || die "uso: $0 <bundle.tar.zst original>"

set -a; source /etc/gf-server/env; set +a

# 1) Portas do gf-server escutando (CLAUDE.md §6: 7777/5560/6543/5567).
log "verificando portas TCP"
fail=0
for pair in ticket:7777 gateway:5560 login:6543 world:5567; do
  name="${pair%%:*}"; port="${pair##*:}"
  if timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    log "  $name ($port) UP"
  else
    err "  $name ($port) DOWN"
    fail=1
  fi
done
(( fail == 0 )) || die "portas faltando — veja journalctl -u 'gf-*.service' -n 100"

# 2) Contagens batem com o manifest do bundle.
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
tar -xf "$BUNDLE" -C "$WORK"
DUMPDIR=$(find "$WORK" -maxdepth 3 -name 'manifest.json' -printf '%h\n' | head -n1)

extract_count() {
  local db="$1" tbl="$2"
  # Parsing simples (grep regex) — manifest é controlado por nós.
  grep -oE "\"db\":\"${db}\"[^}]*\"table\":\"${tbl}\"[^}]*\"count\":[0-9]+" \
       "${DUMPDIR}/manifest.json" | grep -oE '[0-9]+$'
}

cmp_count() {
  local db="$1" tbl="$2" sql="$3"
  local expected actual
  expected=$(extract_count "$db" "$tbl")
  actual=$(sudo -u postgres psql -tAc "$sql" -d "$db")
  if [[ "$expected" == "$actual" ]]; then
    log "  ${db}.${tbl}: ${actual} OK"
  else
    err "  ${db}.${tbl}: esperado=${expected} atual=${actual}"
    return 1
  fi
}

log "verificando contagens vs manifest"
cmp_count gf_ls accounts          'SELECT count(*) FROM accounts'           || fail=1
cmp_count gf_ms tb_user           'SELECT count(*) FROM tb_user'            || fail=1
cmp_count gf_gs player_characters 'SELECT count(*) FROM player_characters'  || fail=1
(( fail == 0 )) || die "contagens divergem do manifest — verifique restore"

# 3) Invariante #1 (id == idnum) — caminho sem dblink, igual ao run-audit.
log "verificando invariante #1 (id == idnum)"
tmp_ls=$(mktemp); tmp_ms=$(mktemp)
sudo -u postgres psql -d gf_ls -tAF$'\t' -c "SELECT id, username FROM accounts ORDER BY id" \
  | sort > "$tmp_ls"
sudo -u postgres psql -d gf_ms -tAF$'\t' -c "SELECT idnum, mid FROM tb_user  ORDER BY idnum" \
  | sort > "$tmp_ms"
diff_out=$(diff "$tmp_ls" "$tmp_ms" || true)
rm -f "$tmp_ls" "$tmp_ms"
if [[ -z "$diff_out" ]]; then
  log "  invariante #1 preservada"
else
  err "  INVARIANTE #1 QUEBRADA — login do jogo vai falhar"
  printf '%s\n' "$diff_out" | head -50
  exit 1
fi

# 4) IP nos bancos casa com o env.
log "verificando IP nos bancos"
ls_ip=$(sudo -u postgres psql -tAc "SELECT DISTINCT ip FROM worlds" -d gf_ls)
gs_ip=$(sudo -u postgres psql -tAc "SELECT DISTINCT ext_address FROM serverstatus WHERE ext_address != 'none'" -d gf_gs)
if [[ "$ls_ip" == "$GF_SERVER_HOST_IP" ]]; then
  log "  gf_ls.worlds.ip = $ls_ip OK"
else
  warn "  gf_ls.worlds.ip = '$ls_ip' (env: $GF_SERVER_HOST_IP)"
fi
if [[ "$gs_ip" == "$GF_SERVER_HOST_IP" ]]; then
  log "  gf_gs.serverstatus.ext_address = $gs_ip OK"
else
  warn "  gf_gs.serverstatus.ext_address = '$gs_ip' (env: $GF_SERVER_HOST_IP)"
fi

log "POST-VALIDATE OK — migração funcional."
