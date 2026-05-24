#!/usr/bin/env bash
# Cria os 3 bancos do GameServer (gf_gs, gf_ls, gf_ms), atribui ao role gf_app
# e carrega os schemas dos dumps .sql.
#
# Idempotente: não dropa bancos existentes. Para reset use `--reset` (com confirmação).
# Para gerenciar permissões no schema 'public' do PG 15+, o role precisa ser OWNER.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
load_env

RESET=0
[[ "${1:-}" == "--reset" ]] && RESET=1

DBS=(gf_gs gf_ls gf_ms)

if (( RESET )); then
  warn "MODO --reset: vai DROPAR e recriar os 3 bancos!"
  confirm "Confirma DROP DATABASE gf_gs/gf_ls/gf_ms?" || die "abortado"
  for db in "${DBS[@]}"; do
    log "DROP DATABASE ${db}"
    psql_super -c "DROP DATABASE IF EXISTS ${db};"
  done
fi

for db in "${DBS[@]}"; do
  exists=$(psql_super -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'")
  if [[ -z "$exists" ]]; then
    log "CREATE DATABASE ${db} OWNER ${GF_DB_USER}"
    psql_super -c "CREATE DATABASE ${db} ENCODING 'UTF8' TEMPLATE template0 OWNER ${GF_DB_USER};"
    sql_file="${GF_SQL_DIR}/${db}.sql"
    [[ -r "$sql_file" ]] || die "schema não encontrado: $sql_file (ajuste GF_SQL_DIR)"
    log "carregando schema $sql_file"
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${db}" -f "${sql_file}"
    # Após carregar como postgres, transfere ownership de tudo para gf_app.
    log "reasignando ownership de objetos em ${db} para ${GF_DB_USER}"
    psql_super -d "${db}" -c "REASSIGN OWNED BY postgres TO ${GF_DB_USER};" 2>/dev/null || true
    # Garante CONNECT explícito (paranoia; já vem por ser owner).
    psql_super -c "GRANT CONNECT ON DATABASE ${db} TO ${GF_DB_USER};"
  else
    log "${db} já existe, mantendo"
  fi
done

# Atualiza IP nos bancos (se as tabelas existem).
log "UPDATE worlds.ip / serverstatus.ext_address com GF_SERVER_HOST_IP=${GF_SERVER_HOST_IP}"
psql_super -d gf_ls -c "UPDATE worlds SET ip = $(sql_lit "$GF_SERVER_HOST_IP");" || warn "gf_ls.worlds não atualizado"
psql_super -d gf_gs -c "UPDATE serverstatus SET ext_address = $(sql_lit "$GF_SERVER_HOST_IP") WHERE ext_address != 'none';" \
  || warn "gf_gs.serverstatus não atualizado"

# Garante a sequence usada pelo painel reescrito e pelo create_account.sh.
log "garantindo gf_ls.account_id_seq_mvp"
psql_super -d gf_ls -c "DO \$\$
DECLARE maxid bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='S' AND relname='account_id_seq_mvp') THEN
    SELECT COALESCE(MAX(id),0) INTO maxid FROM accounts;
    EXECUTE format('CREATE SEQUENCE account_id_seq_mvp START WITH %s OWNED BY accounts.id', maxid + 1);
    EXECUTE 'GRANT USAGE, SELECT, UPDATE ON SEQUENCE account_id_seq_mvp TO ${GF_DB_USER}';
  END IF;
END\$\$;"

log "OK — bancos prontos. Conexão da aplicação: ${GF_DB_USER}@127.0.0.1:5432"
