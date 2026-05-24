#!/usr/bin/env bash
# Backup completo dos 3 bancos (gf_gs/gf_ls/gf_ms) + envio off-site.
#
# Substitui o `./server backup` original. Diferenças críticas:
#   - Sem chmod -R 777 /root (o original fazia, era um buraco).
#   - pg_dump -Fc (custom format): menor + restore paralelo via pg_restore -j.
#     O .sql plain do original era 3-10× maior e impossível de restaurar parcial.
#   - Sha256 por dump + manifest.json com metadados (timestamp, hostname, versão PG,
#     contagem de linhas das tabelas-chave) -> dá pra detectar corrupção e auditar.
#   - Publicação atômica: escreve em $dest.tmp e renomeia depois de tudo OK.
#   - Off-site genérico (rsync-SSH OU rclone) controlado por env.
#   - Retenção local configurável (default 14 dias).
#
# Senha do DB: lida de /etc/gf-server/env (GF_DB_PASSWORD). Não passa em CLI nem
# fica em arquivo .pgpass solto. Roda como root (peer local) -> sudo -u postgres
# tem alternativa, mas precisamos da senha do gf_app pra restaurar onde nao houver
# acesso peer. Aqui usamos `sudo -u postgres pg_dump` que é peer e não vê senha.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/lib.sh"
require_root
load_env
# Carrega também as vars de backup (mesmo /etc/gf-server/env).
: "${GF_BACKUP_DIR:=/var/backups/gf-server}"
: "${GF_BACKUP_RETAIN_DAYS:=14}"
: "${GF_BACKUP_TAG:=$(hostname -s)}"
: "${GF_BACKUP_SSH:=}"
: "${GF_BACKUP_RCLONE:=}"

DBS=(gf_gs gf_ls gf_ms)
TS=$(date -u +%Y%m%dT%H%M%SZ)
STAGE="${GF_BACKUP_DIR}/${TS}.tmp"
FINAL="${GF_BACKUP_DIR}/${TS}"

log "backup destino local: ${FINAL}"
install -d -m 0750 -o root -g root "$STAGE"

# 1) pg_dump -Fc por banco. Custom format já é comprimido (gzip-level 9 interno).
for db in "${DBS[@]}"; do
  out="${STAGE}/${db}.dump"
  log "pg_dump ${db} -> ${out}"
  sudo -u postgres pg_dump -Fc --no-owner --no-privileges -d "$db" -f "$out"
done

# 2) sha256 + tamanhos
log "calculando sha256"
( cd "$STAGE" && sha256sum gf_gs.dump gf_ls.dump gf_ms.dump > SHA256SUMS )

# 3) Snapshot de contagens-chave (smoke test pro restore depois)
log "snapshot de contagens"
c_ls=$(sudo -u postgres psql -tAc 'SELECT count(*) FROM accounts'         -d gf_ls)
c_ms=$(sudo -u postgres psql -tAc 'SELECT count(*) FROM tb_user'          -d gf_ms)
c_gs=$(sudo -u postgres psql -tAc 'SELECT count(*) FROM player_characters' -d gf_gs)
counts=$(printf '[{"db":"gf_ls","table":"accounts","count":%s},{"db":"gf_ms","table":"tb_user","count":%s},{"db":"gf_gs","table":"player_characters","count":%s}]' "$c_ls" "$c_ms" "$c_gs")

pg_version=$(sudo -u postgres psql -tAc 'SHOW server_version_num')

# 4) Manifest
cat > "${STAGE}/manifest.json" <<JSON
{
  "version": 1,
  "timestamp_utc": "${TS}",
  "host": "${GF_BACKUP_TAG}",
  "pg_server_version_num": ${pg_version},
  "format": "pg_dump -Fc",
  "databases": ["gf_gs", "gf_ls", "gf_ms"],
  "counts": ${counts}
}
JSON

# 5) Publicação atômica
mv "$STAGE" "$FINAL"
chmod 0750 "$FINAL"
log "publicado: $FINAL"

# 6) Envio off-site (se configurado).
shipped=0
if [[ -n "$GF_BACKUP_SSH" ]]; then
  log "rsync -> ${GF_BACKUP_SSH}"
  # Sub-pasta por timestamp; rsync preserva permissões e usa SSH como transporte.
  rsync -az --partial --info=progress2 "${FINAL}/" "${GF_BACKUP_SSH%/}/${TS}/"
  shipped=1
fi
if [[ -n "$GF_BACKUP_RCLONE" ]]; then
  require_cmd rclone
  log "rclone copy -> ${GF_BACKUP_RCLONE}"
  rclone copy --progress "${FINAL}" "${GF_BACKUP_RCLONE%/}/${TS}/"
  shipped=1
fi
if (( ! shipped )); then
  warn "nenhum destino off-site configurado (GF_BACKUP_SSH / GF_BACKUP_RCLONE). Backup só local."
fi

# 7) Retenção local
log "retenção local: removendo backups com mais de ${GF_BACKUP_RETAIN_DAYS} dias"
find "${GF_BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d \
  -regex '.*/[0-9]\{8\}T[0-9]\{6\}Z$' \
  -mtime "+${GF_BACKUP_RETAIN_DAYS}" -print -exec rm -rf {} +

log "OK — backup concluído: ${FINAL}"
