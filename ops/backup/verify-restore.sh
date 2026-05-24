#!/usr/bin/env bash
# Smoke test do backup: restaura para bancos TEMPORÁRIOS, valida contagens,
# checa invariantes críticas e descarta. NÃO toca os bancos de produção.
#
# Uso: ./verify-restore.sh [<diretório do backup>]
#      (default: o backup mais recente em $GF_BACKUP_DIR)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root
load_env
: "${GF_BACKUP_DIR:=/var/backups/gf-server}"

BACKUP_DIR="${1:-}"
if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR=$(ls -1d "${GF_BACKUP_DIR}"/[0-9]*Z 2>/dev/null | sort | tail -n1 || true)
  [[ -n "$BACKUP_DIR" ]] || die "nenhum backup encontrado em ${GF_BACKUP_DIR}"
fi
log "verificando: $BACKUP_DIR"

for f in gf_gs.dump gf_ls.dump gf_ms.dump SHA256SUMS manifest.json; do
  [[ -r "${BACKUP_DIR}/${f}" ]] || die "faltando: ${BACKUP_DIR}/${f}"
done

log "checando SHA256SUMS"
( cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS )

SUFFIX="verify_$(date +%s)"
DBS_TMP=("gf_gs_${SUFFIX}" "gf_ls_${SUFFIX}" "gf_ms_${SUFFIX}")

cleanup() {
  for d in "${DBS_TMP[@]}"; do
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${d};" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

log "criando bancos temporários"
for d in "${DBS_TMP[@]}"; do
  sudo -u postgres psql -c "CREATE DATABASE ${d} ENCODING 'UTF8' TEMPLATE template0;"
done

log "pg_restore (paralelo -j2)"
sudo -u postgres pg_restore -j2 --no-owner --no-privileges -d "gf_gs_${SUFFIX}" "${BACKUP_DIR}/gf_gs.dump"
sudo -u postgres pg_restore -j2 --no-owner --no-privileges -d "gf_ls_${SUFFIX}" "${BACKUP_DIR}/gf_ls.dump"
sudo -u postgres pg_restore -j2 --no-owner --no-privileges -d "gf_ms_${SUFFIX}" "${BACKUP_DIR}/gf_ms.dump"

log "validando contagens vs manifest"
expected_ls=$(grep -oE '"db":"gf_ls"[^}]*"count":[0-9]+' "${BACKUP_DIR}/manifest.json" | grep -oE '[0-9]+$')
expected_ms=$(grep -oE '"db":"gf_ms"[^}]*"count":[0-9]+' "${BACKUP_DIR}/manifest.json" | grep -oE '[0-9]+$')
expected_gs=$(grep -oE '"db":"gf_gs"[^}]*"count":[0-9]+' "${BACKUP_DIR}/manifest.json" | grep -oE '[0-9]+$')

actual_ls=$(sudo -u postgres psql -tAc 'SELECT count(*) FROM accounts'         -d "gf_ls_${SUFFIX}")
actual_ms=$(sudo -u postgres psql -tAc 'SELECT count(*) FROM tb_user'          -d "gf_ms_${SUFFIX}")
actual_gs=$(sudo -u postgres psql -tAc 'SELECT count(*) FROM player_characters' -d "gf_gs_${SUFFIX}")

check() {
  local label="$1" exp="$2" act="$3"
  if [[ "$exp" == "$act" ]]; then
    log "  ${label}: ${act} OK"
  else
    die "${label}: esperado ${exp}, obtido ${act}"
  fi
}
check "gf_ls.accounts"         "$expected_ls" "$actual_ls"
check "gf_ms.tb_user"           "$expected_ms" "$actual_ms"
check "gf_gs.player_characters" "$expected_gs" "$actual_gs"

log "validando invariante crítica id == idnum (CLAUDE.md §6 #1)"
# Coleta os pares e compara. Se houver alguma dessincronia, o servidor recusaria login
# após restore. Detectar aqui é mais barato que descobrir em produção.
mismatch=$(sudo -u postgres psql -tAF$'\t' -d "gf_ls_${SUFFIX}" \
  -c "SELECT id, username FROM accounts ORDER BY id" \
  | while IFS=$'\t' read -r id user; do
      idnum=$(sudo -u postgres psql -tAc "SELECT idnum FROM tb_user WHERE mid='${user//\'/}'" -d "gf_ms_${SUFFIX}" || echo "")
      if [[ "$id" != "$idnum" ]]; then
        echo "DESSINC user=${user} ls.id=${id} ms.idnum=${idnum}"
      fi
    done)
if [[ -n "$mismatch" ]]; then
  echo "$mismatch" >&2
  die "invariante id==idnum quebrada no backup — restore corromperia o login"
fi
log "  todos os ids casam"

log "OK — backup ${BACKUP_DIR} restaurável e consistente"
