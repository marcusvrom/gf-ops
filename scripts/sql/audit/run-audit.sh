#!/usr/bin/env bash
# Roda todas as queries de auditoria contra os 3 bancos do gf-server.
# Não escreve nada nos bancos. Sem dependência de dblink.
#
# Uso:
#   sudo bash scripts/sql/audit/run-audit.sh                     # imprime + arquiva
#   sudo bash scripts/sql/audit/run-audit.sh --no-archive        # só stdout
#   sudo bash scripts/sql/audit/run-audit.sh --quick             # pula queries lentas (auction)
#
# Saída arquivada em /var/log/gf-audit/YYYYMMDD-HHMMSS.log
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../ops/install/lib.sh"
require_root

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE=1
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --no-archive) ARCHIVE=0 ;;
    --quick)      QUICK=1 ;;
    *) die "uso: $0 [--no-archive] [--quick]" ;;
  esac
done

TS=$(date +%Y%m%d-%H%M%S)
if (( ARCHIVE )); then
  install -d -m 0750 -o root -g root /var/log/gf-audit
  OUT="/var/log/gf-audit/${TS}.log"
  exec > >(tee -a "$OUT") 2>&1
fi

PSQL='sudo -u postgres psql -v ON_ERROR_STOP=1 --quiet'

section() { printf '\n========== %s ==========\n' "$*"; }

section "01-gold-flux (gf_gs)"
$PSQL -d gf_gs -f "${HERE}/01-gold-flux.sql"

section "02-gold-distribution (gf_gs)"
$PSQL -d gf_gs -f "${HERE}/02-gold-distribution.sql"

section "03-gold-outliers (gf_gs)"
$PSQL -d gf_gs -f "${HERE}/03-gold-outliers.sql"

section "04-ap-cap (gf_ms)"
$PSQL -d gf_ms -f "${HERE}/04-ap-cap.sql"

if (( ! QUICK )); then
  section "05-auction-extremes (gf_gs)"
  $PSQL -d gf_gs -f "${HERE}/05-auction-extremes.sql"
fi

section "06-gm-privilege (3 partes)"
echo "--- gf_gs: chars com privilege=5 ---"
$PSQL -d gf_gs -f "${HERE}/06-gm-privilege.sql" || true
echo "--- gf_ls: gm_tool_accounts ---"
$PSQL -d gf_ls -f "${HERE}/06-gm-privilege.sql" || true
echo "--- gf_ms: tb_user.byauthority ---"
$PSQL -d gf_ms -f "${HERE}/06-gm-privilege.sql" || true

section "07-invariant id==idnum (caminho sem dblink)"
# Em vez de instalar dblink, fazemos dois SELECTs separados, ordenamos e usamos
# comm/diff. Mais robusto: detecta tanto dessincronia de valor quanto chaves órfãs.
tmp_ls=$(mktemp); tmp_ms=$(mktemp)
trap 'rm -f "$tmp_ls" "$tmp_ms"' EXIT
$PSQL -d gf_ls -tAF$'\t' -c "SELECT id, username FROM accounts ORDER BY id" \
  | awk -F'\t' 'NF==2 {print $1"\t"$2}' | sort > "$tmp_ls"
$PSQL -d gf_ms -tAF$'\t' -c "SELECT idnum, mid FROM tb_user  ORDER BY idnum" \
  | awk -F'\t' 'NF==2 {print $1"\t"$2}' | sort > "$tmp_ms"

n_ls=$(wc -l < "$tmp_ls")
n_ms=$(wc -l < "$tmp_ms")
echo "gf_ls.accounts: ${n_ls} | gf_ms.tb_user: ${n_ms}"

diff_out=$(diff "$tmp_ls" "$tmp_ms" || true)
if [[ -z "$diff_out" ]]; then
  echo "OK — id == idnum para TODAS as contas. Invariante #1 preservada."
else
  echo "ATENÇÃO: divergências detectadas (formato diff: < gf_ls, > gf_ms):"
  printf '%s\n' "$diff_out" | head -100
  echo "Cada par discrepante quebraria 'Erro de Sistema' no login."
fi

if (( ARCHIVE )); then
  echo
  log "relatório salvo em $OUT"
fi
