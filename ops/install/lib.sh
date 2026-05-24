# shellcheck shell=bash
# Helpers compartilhados pelos scripts de install. Source-only.
# Uso: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

readonly GF_ENV_FILE="${GF_ENV_FILE:-/etc/gf-server/env}"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] ERR: %s\n'  "$(date +%H:%M:%S)" "$*" >&2; }
die()  { err "$*"; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "rode como root (sudo)"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "comando ausente: $1"
}

# Carrega /etc/gf-server/env (modo 0600 obrigatório).
# Variáveis esperadas:
#   GF_DB_PASSWORD        senha do role gf_app no PostgreSQL
#   GF_SERVER_HOST_IP     IP exposto ao client (gravado nos binários e nos bancos)
#   GF_SERVER_ROOT        diretório dos binários (default /root/gf_server)
#   GF_SQL_DIR            dumps .sql do server file (default $GF_SERVER_ROOT/_utils/db)
load_env() {
  [[ -r "$GF_ENV_FILE" ]] || die "$GF_ENV_FILE não existe ou não é legível. Copie env.example e ajuste."
  local mode; mode=$(stat -c '%a' "$GF_ENV_FILE")
  [[ "$mode" == "600" ]] || die "$GF_ENV_FILE deve ter modo 600 (atual: $mode). Rode: chmod 600 $GF_ENV_FILE"
  local owner; owner=$(stat -c '%U' "$GF_ENV_FILE")
  [[ "$owner" == "root" ]] || die "$GF_ENV_FILE deve ser do root (atual: $owner)"
  # shellcheck disable=SC1090
  set -a; source "$GF_ENV_FILE"; set +a
  : "${GF_DB_PASSWORD:?GF_DB_PASSWORD não definido em $GF_ENV_FILE}"
  : "${GF_SERVER_HOST_IP:?GF_SERVER_HOST_IP não definido em $GF_ENV_FILE}"
  export GF_SERVER_ROOT="${GF_SERVER_ROOT:-/root/gf_server}"
  export GF_SQL_DIR="${GF_SQL_DIR:-${GF_SERVER_ROOT}/_utils/db}"
}

confirm() {
  local prompt="${1:-prosseguir?}"
  read -r -p "$prompt [s/N] " ans
  [[ "$ans" =~ ^[sSyY]$ ]]
}

# Escapa para uso em SQL como literal (sem placeholder).
# Use SOMENTE para psql -c em valores controlados (não para input externo).
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

# Roda psql como superuser local. Idempotência fica por conta do SQL chamado.
psql_super() {
  sudo -u postgres psql -v ON_ERROR_STOP=1 "$@"
}
