#!/usr/bin/env bash
# Patch hex do IP em WorldServer e ZoneServer.
# Equivalente endurecido do `./install ip` original.
#
# Diferenças:
#   - Backup .bak SÓ se ainda não existir (não sobrescreve o original).
#   - Calcula e registra sha256 antes/depois em /var/lib/gf-server/ip-patch.log.
#   - Aceita --dry-run para imprimir o que faria, sem escrever.
#   - Valida o IP (formato e que NÃO é loopback) antes do dd.
#   - Sem chmod 777 em nada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
load_env

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

readonly WORLD_OFFSET=0x3EA7A7
readonly ZONE_OFFSET=0x822D47

validate_ip() {
  local ip="$1"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "GF_SERVER_HOST_IP inválido: $ip"
  IFS=. read -r a b c d <<< "$ip"
  for o in "$a" "$b" "$c" "$d"; do (( o <= 255 )) || die "octeto > 255: $ip"; done
  [[ "$a" != "127" ]] || die "GF_SERVER_HOST_IP é loopback — o client em outra máquina nunca alcança 127.0.0.1"
}
validate_ip "$GF_SERVER_HOST_IP"

# Reproduz a transformação do script original:
#   1) zera o último octeto (vira endereço de rede)
#   2) converte cada char ASCII do IP textual para 2 hex bytes
#   3) adiciona padding de "000000" (3 bytes null) ao final
IFS=. read -r a b c _ <<< "$GF_SERVER_HOST_IP"
NET_IP="${a}.${b}.${c}.0"

hex=""
for ((i=0; i<${#NET_IP}; i++)); do
  hex+=$(printf '%02x' "'${NET_IP:$i:1}")
done
hex+="000000"
PATCH_BYTES=$(echo "$hex" | sed 's/\(..\)/\\x\1/g')

log "IP patch: alvo=${NET_IP} (último octeto zerado), ${#hex} bytes hex"

patch_one() {
  local label="$1" relpath="$2" offset="$3"
  local bin="${GF_SERVER_ROOT}/${relpath}"
  [[ -f "$bin" ]] || die "binário não encontrado: $bin"

  local bak="${bin}.bak"
  if [[ ! -f "$bak" ]]; then
    log "${label}: criando backup original ${bak}"
    (( DRY )) || cp -a "$bin" "$bak"
  else
    log "${label}: .bak já existe, mantendo o original intacto"
  fi

  local sha_before; sha_before=$(sha256sum "$bin" | awk '{print $1}')

  if (( DRY )); then
    log "${label}: DRY-RUN dd seek=${offset} (${#hex} bytes) — não escrevendo"
    return
  fi

  # shellcheck disable=SC2059
  printf "${PATCH_BYTES}" \
    | dd of="$bin" bs=1 seek=$((offset)) count=$((${#hex}/2)) conv=notrunc status=none

  local sha_after; sha_after=$(sha256sum "$bin" | awk '{print $1}')
  log "${label}: sha256 ${sha_before} → ${sha_after}"

  # Audit trail.
  install -d -m 0750 /var/lib/gf-server
  printf '%s  %s  ip=%s  offset=%s  before=%s  after=%s\n' \
    "$(date -Iseconds)" "$bin" "$NET_IP" "$offset" "$sha_before" "$sha_after" \
    >> /var/lib/gf-server/ip-patch.log
}

patch_one "WorldServer" "WorldServer/WorldServer" "$WORLD_OFFSET"
patch_one "ZoneServer"  "ZoneServer/ZoneServer"   "$ZONE_OFFSET"

if (( ! DRY )); then
  log "atualizando IP nos bancos"
  psql_super -d gf_ls -c "UPDATE worlds SET ip = $(sql_lit "$GF_SERVER_HOST_IP");"
  psql_super -d gf_gs -c "UPDATE serverstatus SET ext_address = $(sql_lit "$GF_SERVER_HOST_IP") WHERE ext_address != 'none';"
fi

log "OK — IP patch concluído. Audit log: /var/lib/gf-server/ip-patch.log"
