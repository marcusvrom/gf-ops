#!/usr/bin/env bash
# Instala PostgreSQL 13 (apt.postgresql.org), endurece a config e cria o role 'gf_app'.
#
# Diferenças do install original:
#   - NÃO purga PostgreSQL existente (instalação destrutiva quebra deploys).
#   - listen_addresses = 'localhost' (NÃO '*').
#   - pg_hba.conf: 127.0.0.1/32 + ::1/128 scram-sha-256 (NÃO 0.0.0.0/0).
#   - Cria role 'gf_app' SEM SUPERUSER, SEM CREATEDB, SEM CREATEROLE.
#   - Senha do postgres (peer/local) intocada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
load_env

PG_VERSION="${PG_VERSION:-13}"
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"

log "instalando repositório oficial pg + postgresql-${PG_VERSION}"
if [[ ! -f /etc/apt/sources.list.d/pgdg.list ]]; then
  install -m 0644 /dev/null /etc/apt/trusted.gpg.d/pgsql.gpg
  wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor > /etc/apt/trusted.gpg.d/pgsql.gpg
  . /etc/os-release
  echo "deb http://apt.postgresql.org/pub/repos/apt/ ${VERSION_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list
  apt-get update -y
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y "postgresql-${PG_VERSION}"

[[ -d "$PG_CONF_DIR" ]] || die "diretório de config do PG não encontrado: $PG_CONF_DIR"

log "endurecendo postgresql.conf (listen_addresses = 'localhost')"
# Backup uma única vez.
[[ -f "${PG_CONF_DIR}/postgresql.conf.bak.gf-ops" ]] \
  || cp -a "${PG_CONF_DIR}/postgresql.conf" "${PG_CONF_DIR}/postgresql.conf.bak.gf-ops"
# Append controlado: a ÚLTIMA atribuição prevalece no PG, então não precisamos
# editar a linha original. Idempotente via marcador.
if ! grep -q '# gf-ops: hardened listen' "${PG_CONF_DIR}/postgresql.conf"; then
  cat >> "${PG_CONF_DIR}/postgresql.conf" <<'EOF'

# gf-ops: hardened listen — mantém o serviço só em loopback.
listen_addresses = 'localhost'
EOF
fi

log "endurecendo pg_hba.conf (sem 0.0.0.0/0)"
[[ -f "${PG_CONF_DIR}/pg_hba.conf.bak.gf-ops" ]] \
  || cp -a "${PG_CONF_DIR}/pg_hba.conf" "${PG_CONF_DIR}/pg_hba.conf.bak.gf-ops"
# Remove regras explicitamente abertas que o install original deixava.
sed -i -E '/0\.0\.0\.0\/0/d' "${PG_CONF_DIR}/pg_hba.conf"
# Garante loopback IPv4/IPv6 com scram-sha-256 (PG 13 default).
if ! grep -qE '^host\s+all\s+all\s+127\.0\.0\.1/32\s+scram-sha-256' "${PG_CONF_DIR}/pg_hba.conf"; then
  printf '\n# gf-ops: hardened auth\nhost  all  all  127.0.0.1/32  scram-sha-256\nhost  all  all  ::1/128       scram-sha-256\n' \
    >> "${PG_CONF_DIR}/pg_hba.conf"
fi

log "reiniciando postgresql"
systemctl enable --now "postgresql"
systemctl restart "postgresql"

log "garantindo role '${GF_DB_USER}' (sem superuser/createdb/createrole)"
# Idempotente: cria se não existir, sempre re-aplica a senha vinda do env.
psql_super -tAc "DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${GF_DB_USER}') THEN
    CREATE ROLE ${GF_DB_USER} LOGIN PASSWORD $(sql_lit "$GF_DB_PASSWORD")
      NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  ELSE
    ALTER ROLE ${GF_DB_USER} WITH LOGIN PASSWORD $(sql_lit "$GF_DB_PASSWORD")
      NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
END\$\$;"

log "OK — PostgreSQL endurecido. Role: ${GF_DB_USER} (sem privilégio de servidor)."
log "    backups: ${PG_CONF_DIR}/postgresql.conf.bak.gf-ops, pg_hba.conf.bak.gf-ops"
