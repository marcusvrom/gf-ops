#!/usr/bin/env bash
# RESTAURA os 3 bancos de produção a partir de um backup.
# É a operação destrutiva — exige --yes-i-really-mean-it explícito.
#
# Uso: ./restore.sh <diretório do backup> --yes-i-really-mean-it
#
# Pré-req: o servidor deve estar PARADO (systemctl stop gf.target).
#          Falha se houver conexões ativas nos bancos.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root
load_env

BACKUP_DIR="${1:-}"
CONFIRM="${2:-}"

[[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || die "uso: $0 <backup_dir> --yes-i-really-mean-it"
[[ "$CONFIRM" == "--yes-i-really-mean-it" ]] || die "operação destrutiva requer --yes-i-really-mean-it"

for f in gf_gs.dump gf_ls.dump gf_ms.dump SHA256SUMS manifest.json; do
  [[ -r "${BACKUP_DIR}/${f}" ]] || die "faltando: ${BACKUP_DIR}/${f}"
done

log "checando integridade (sha256)"
( cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS )

# Se gf.target está ativo, recusa: restore com servidor de pé corrompe estado.
if systemctl is-active --quiet gf.target 2>/dev/null; then
  die "gf.target está ativo. Pare antes: systemctl stop gf.target"
fi

# Conexões ativas nos bancos => DROP DATABASE falha. Mostra quem está conectado.
for db in gf_gs gf_ls gf_ms; do
  n=$(sudo -u postgres psql -tAc "SELECT count(*) FROM pg_stat_activity WHERE datname='${db}' AND pid <> pg_backend_pid()")
  if [[ "$n" != "0" ]]; then
    warn "${db}: ${n} conexão(ões) ativa(s). Encerrando."
    sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db}' AND pid <> pg_backend_pid();" >/dev/null
  fi
done

log "DROP + CREATE + pg_restore dos 3 bancos"
for db in gf_gs gf_ls gf_ms; do
  log "restaurando ${db}"
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${db};"
  sudo -u postgres psql -c "CREATE DATABASE ${db} ENCODING 'UTF8' TEMPLATE template0 OWNER ${GF_DB_USER};"
  sudo -u postgres pg_restore -j2 --no-owner --no-privileges -d "${db}" "${BACKUP_DIR}/${db}.dump"
  # Owner pós-restore (pg_restore --no-owner deixa tudo como postgres).
  sudo -u postgres psql -d "${db}" -c "REASSIGN OWNED BY postgres TO ${GF_DB_USER};" 2>/dev/null || true
done

# Restaura a sequence MVP se a tabela accounts existir.
sudo -u postgres psql -d gf_ls <<SQL
DO \$\$
DECLARE maxid bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='S' AND relname='account_id_seq_mvp') THEN
    SELECT COALESCE(MAX(id),0) INTO maxid FROM accounts;
    EXECUTE format('CREATE SEQUENCE account_id_seq_mvp START WITH %s OWNED BY accounts.id', maxid + 1);
    EXECUTE 'GRANT USAGE, SELECT, UPDATE ON SEQUENCE account_id_seq_mvp TO ${GF_DB_USER}';
  ELSE
    PERFORM setval('account_id_seq_mvp', GREATEST(nextval('account_id_seq_mvp'), (SELECT COALESCE(MAX(id),0)+1 FROM accounts)));
  END IF;
END\$\$;
SQL

log "OK — restore concluído. Subir o servidor: systemctl start gf.target"
