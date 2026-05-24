#!/bin/bash
# create_account.sh — cria conta GF garantindo as invariantes críticas:
#   gf_ls.accounts.id == gf_ms.tb_user.idnum
#   senha em MD5 nos dois bancos
#   ID gerado de forma ATÔMICA (sem race condition do MAX(id)+1)
#
# Uso: ./create_account.sh <username> <senha> [is_gm]
#   is_gm opcional: "gm" eleva a conta (privilege/byauthority = 5)
#
# Pré-req: PGPASSWORD exportado ou ~/.pgpass configurado.
set -euo pipefail

PGHOST="${PGHOST:-127.0.0.1}"
PGUSER="${PGUSER:-postgres}"
USER_GF="${1:?uso: $0 <username> <senha> [gm]}"
PASS_RAW="${2:?uso: $0 <username> <senha> [gm]}"
IS_GM="${3:-}"

# MD5 da senha (formato que o servidor legado espera)
PASS_MD5="$(printf '%s' "$PASS_RAW" | md5sum | awk '{print $1}')"
AUTH=0; [ "$IS_GM" = "gm" ] && AUTH=5

psql_ls() { psql -h "$PGHOST" -U "$PGUSER" -d gf_ls -v ON_ERROR_STOP=1 "$@"; }
psql_ms() { psql -h "$PGHOST" -U "$PGUSER" -d gf_ms -v ON_ERROR_STOP=1 "$@"; }

# 1) rejeitar duplicado
if [ "$(psql_ls -Atc "SELECT count(*) FROM accounts WHERE username='${USER_GF}'")" != "0" ]; then
  echo "ERRO: username '${USER_GF}' já existe em gf_ls.accounts" >&2; exit 1
fi

# 2) ID atômico via sequence dedicada (resolve a race condition do MAX(id)+1).
#    A sequence é criada uma vez e inicia acima do maior id atual.
psql_ls <<SQL
DO \$\$
DECLARE maxid bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='S' AND relname='account_id_seq_mvp') THEN
    SELECT COALESCE(MAX(id),0) INTO maxid FROM accounts;
    EXECUTE format('CREATE SEQUENCE account_id_seq_mvp START WITH %s', maxid + 1);
  END IF;
END
\$\$;
SQL

NEW_ID="$(psql_ls -Atc "SELECT nextval('account_id_seq_mvp')")"
echo ">> Novo account id (atômico): ${NEW_ID}"

# 3) inserir nos DOIS bancos com o MESMO id. Se o segundo falhar, desfaz o primeiro.
if ! psql_ls -c "INSERT INTO accounts
   (id, username, password, realname, worldserver, use_charpassword, state, char_max_num, win_os_bit)
   VALUES (${NEW_ID}, '${USER_GF}', '${PASS_MD5}', '${USER_GF}', 0, false, 0, 3, 0);"; then
  echo "ERRO ao inserir em gf_ls.accounts" >&2; exit 1
fi

if ! psql_ms -c "INSERT INTO tb_user
   (mid, password, pwd, idnum, byauthority, pvalues, billingrule, status, bonus)
   VALUES ('${USER_GF}', '${PASS_MD5}', '${PASS_MD5}', ${NEW_ID}, ${AUTH}, 99999, 0, 0, 0);"; then
  echo "ERRO ao inserir em gf_ms.tb_user — desfazendo gf_ls.accounts" >&2
  psql_ls -c "DELETE FROM accounts WHERE id=${NEW_ID};" || true
  exit 1
fi

# 4) verificação da invariante
LS_ID="$(psql_ls -Atc "SELECT id FROM accounts WHERE username='${USER_GF}'")"
MS_ID="$(psql_ms -Atc "SELECT idnum FROM tb_user WHERE mid='${USER_GF}'")"
if [ "$LS_ID" = "$MS_ID" ]; then
  echo "OK: conta '${USER_GF}' criada. id=${LS_ID} (gf_ls) == idnum=${MS_ID} (gf_ms). GM=${AUTH}"
else
  echo "FALHA DE INVARIANTE: id=${LS_ID} != idnum=${MS_ID}" >&2; exit 1
fi
