#!/usr/bin/env bash
# 03-pg-localhost.sh — endurece a rede do PostgreSQL.
#
# 1) listen_addresses = 'localhost' (idempotente via marcador).
# 2) Remove regras 0.0.0.0/0 do pg_hba (legado do install original).
# 3) Garante 127.0.0.1/32 + ::1/128 com método 'md5'.
#
# DECISÃO sobre md5 vs scram-sha-256 (registrada também no README):
#   Os binários ELF do GameServer são da era ~2006/2008, anteriores ao SCRAM
#   (PG10/2017). Usam um libpq legado que SÓ FALA md5. Usar 'scram-sha-256'
#   na linha 127.0.0.1/32 quebra o login do jogo (mensagem "Erro de Sistema"
#   pelo lado do client, ECONNREFUSED-ish do lado do PG). O painel (PDO
#   moderno) aceita md5 sem perda. Como a conexão é puramente loopback
#   (listen_addresses=localhost), o ganho de SCRAM seria marginal.
#
# Idempotente: re-rodar não duplica linha nem perde o .bak original.
# Backup nominal: postgresql.conf.bak.gf-ops e pg_hba.conf.bak.gf-ops na 1ª vez;
# backup datado .bak.<ts> antes de cada modificação ulterior.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root

PG_VERSION="${PG_VERSION:-13}"
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
[[ -d "$PG_CONF_DIR" ]] || die "config do PG não encontrada: $PG_CONF_DIR"

TS=$(date +%Y%m%d-%H%M%S)
bak_once() {
  local f="$1"
  [[ -f "${f}.bak.gf-ops" ]] || cp -a "$f" "${f}.bak.gf-ops"
  cp -a "$f" "${f}.bak.${TS}"
}

# ---------- postgresql.conf ----------
PG_CONF="${PG_CONF_DIR}/postgresql.conf"
bak_once "$PG_CONF"

if ! grep -q '# gf-ops: hardened listen' "$PG_CONF"; then
  log "anexando listen_addresses='localhost' em $PG_CONF"
  cat >> "$PG_CONF" <<'EOF'

# gf-ops: hardened listen — mantém o serviço só em loopback.
listen_addresses = 'localhost'
EOF
else
  log "listen_addresses já endurecido (marcador presente)"
fi

# ---------- pg_hba.conf ----------
HBA="${PG_CONF_DIR}/pg_hba.conf"
bak_once "$HBA"

# Remove regras explicitamente abertas (legado do install original).
if grep -qE '0\.0\.0\.0/0' "$HBA"; then
  log "removendo regras 0.0.0.0/0 de $HBA"
  sed -i -E '/0\.0\.0\.0\/0/d' "$HBA"
fi

# Remove qualquer linha host... 127.0.0.1/32 com scram-sha-256 (que esta unit
# ou um install anterior possa ter deixado). Caso md5 já exista, o append abaixo
# vira no-op via marcador.
sed -i -E '/^host\s+all\s+all\s+127\.0\.0\.1\/32\s+scram-sha-256/d' "$HBA"
sed -i -E '/^host\s+all\s+all\s+::1\/128\s+scram-sha-256/d'         "$HBA"

if ! grep -q '# gf-ops: hardened auth (md5 by design)' "$HBA"; then
  log "anexando regras host md5 (127.0.0.1/32 + ::1/128) em $HBA"
  cat >> "$HBA" <<'EOF'

# gf-ops: hardened auth (md5 by design — binários ELF legados não falam SCRAM).
# Localhost only; listen_addresses=localhost garante que nada vem da rede.
host  all  all  127.0.0.1/32  md5
host  all  all  ::1/128       md5
EOF
else
  log "regras md5 já endurecidas (marcador presente)"
fi

# ---------- reload (não restart — pg_hba e listen exigem reload + restart resp.) ----------
# postgresql.conf -> listen_addresses pede RESTART para tomar efeito; pg_hba pede
# só RELOAD. Como já estamos endurecendo, fazemos reload aqui (idempotente, vivo)
# e instrui restart abaixo (decisão humana — pode coincidir com janela de manutenção).
log "reload do postgresql (aplica pg_hba)"
systemctl reload postgresql

cat <<INFO

ATENÇÃO:
  listen_addresses mudou — para tomar efeito é preciso RESTART do PostgreSQL.
  Faça em janela de manutenção (vai derrubar gf.target enquanto sobe de novo):

    sudo systemctl stop gf.target
    sudo systemctl restart postgresql
    sudo systemctl start gf.target

  Antes do restart, valide:
    sudo grep -nE '^(listen_addresses|host)' $PG_CONF $HBA

Backups deste run em ${PG_CONF}.bak.${TS} e ${HBA}.bak.${TS}.
Backup nominal (1ª vez) em *.bak.gf-ops.
INFO

log "OK"
