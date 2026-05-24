#!/usr/bin/env bash
# Pré-requisitos de SO p/ os binários 32-bit do GameServer.
# Idempotente. NÃO purga pacotes (diferente do `install full` original).
#
# Garante as invariantes #3 do CLAUDE.md:
#   - locale C
#   - libs i386 (libc6:i386, libstdc++6:i386, libgcc-s1:i386, zlib1g:i386)
#   - nscd ativo
#   - hosts: files dns
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root

log "atualizando lista de pacotes"
apt-get update -y

log "adicionando arquitetura i386"
if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
  dpkg --add-architecture i386
  apt-get update -y
fi

log "instalando libs 32-bit + nscd + locales"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386 \
  nscd locales ca-certificates

log "garantindo locale C"
if ! locale -a | grep -qiE '^C(\..+)?$'; then
  locale-gen C
fi
update-locale LANG=C LC_ALL=C >/dev/null

log "habilitando nscd"
systemctl enable --now nscd

log "checando /etc/nsswitch.conf (esperado: 'hosts: files dns')"
if ! grep -qE '^hosts:\s*files\s+dns' /etc/nsswitch.conf; then
  warn "ajustando /etc/nsswitch.conf"
  sed -i.bak -E 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
fi

log "OK — pré-requisitos de SO satisfeitos"
