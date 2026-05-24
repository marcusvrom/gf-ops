#!/usr/bin/env bash
# Instala postgres_exporter como binário (não há pacote estável no apt).
# Cria role 'gf_exporter' com pg_monitor (privilégio mínimo p/ leitura de stats).
# Roda como user de sistema 'pg_exporter'. Listening em :9187.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root
load_env

VERSION="${POSTGRES_EXPORTER_VERSION:-0.15.0}"
ARCH=$(dpkg --print-architecture)   # amd64/arm64
case "$ARCH" in
  amd64) ARCH_GO=linux-amd64 ;;
  arm64) ARCH_GO=linux-arm64 ;;
  *)     die "arquitetura não suportada: $ARCH" ;;
esac

TARBALL="postgres_exporter-${VERSION}.${ARCH_GO}.tar.gz"
URL="https://github.com/prometheus-community/postgres_exporter/releases/download/v${VERSION}/${TARBALL}"
DST=/usr/local/bin/postgres_exporter

if [[ ! -x "$DST" ]] || ! "$DST" --version 2>&1 | grep -q "${VERSION}"; then
  log "baixando postgres_exporter ${VERSION}"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$URL" -o "${tmp}/${TARBALL}"
  tar -xzf "${tmp}/${TARBALL}" -C "$tmp"
  install -m 0755 "${tmp}/postgres_exporter-${VERSION}.${ARCH_GO}/postgres_exporter" "$DST"
fi

log "criando user de sistema 'pg_exporter'"
id -u pg_exporter >/dev/null 2>&1 \
  || useradd --system --no-create-home --shell /usr/sbin/nologin pg_exporter

log "gerando senha aleatória + role gf_exporter (pg_monitor, leitura)"
# Senha randômica para o role do exporter; só vive em /etc/gf-server/exporter.env (0600).
EXP_PWD=$(openssl rand -base64 24 | tr -d '\n=+/')
install -d -m 0750 -o root -g root /etc/gf-server
cat > /etc/gf-server/exporter.env <<EOF
# Gerado automaticamente. NÃO editar manualmente.
DATA_SOURCE_NAME=postgresql://gf_exporter:${EXP_PWD}@127.0.0.1:5432/postgres?sslmode=disable
# Custom queries opcionais (queries.yml apontando para tabelas do gf_gs/gf_ls/gf_ms):
PG_EXPORTER_EXTEND_QUERY_PATH=/etc/gf-server/postgres-exporter-queries.yml
EOF
chown root:pg_exporter /etc/gf-server/exporter.env
chmod 0640             /etc/gf-server/exporter.env

# Cria role + pg_monitor + senha (idempotente).
psql_super -tAc "DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gf_exporter') THEN
    CREATE ROLE gf_exporter LOGIN PASSWORD $(sql_lit "$EXP_PWD")
      NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT IN ROLE pg_monitor;
  ELSE
    ALTER ROLE gf_exporter WITH LOGIN PASSWORD $(sql_lit "$EXP_PWD") IN ROLE pg_monitor;
  END IF;
END\$\$;"

# Permite que gf_exporter conecte nos 3 bancos (necessário para custom queries).
for db in gf_gs gf_ls gf_ms; do
  psql_super -c "GRANT CONNECT ON DATABASE ${db} TO gf_exporter;"
  # Leitura nas tabelas do gf_gs para custom queries (auditoria de economia).
  # pg_monitor já dá visão de stats; aqui adicionamos SELECT em tabelas de negócio.
  psql_super -d "$db" -c "GRANT USAGE ON SCHEMA public TO gf_exporter;"
  psql_super -d "$db" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO gf_exporter;"
  psql_super -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO gf_exporter;"
done

log "instalando custom queries (auditoria de economia)"
install -m 0644 "$(dirname "${BASH_SOURCE[0]}")/postgres-exporter-queries.yml" \
                /etc/gf-server/postgres-exporter-queries.yml

log "instalando unit"
install -m 0644 "$(dirname "${BASH_SOURCE[0]}")/postgres-exporter.service" \
                /etc/systemd/system/postgres-exporter.service
systemctl daemon-reload
systemctl enable --now postgres-exporter
log "OK — postgres_exporter em :9187 (role gf_exporter, pg_monitor)"
ss -ltn '( sport = :9187 )' || true
