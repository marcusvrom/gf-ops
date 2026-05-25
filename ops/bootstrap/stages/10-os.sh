#!/usr/bin/env bash
# stage 10 — pré-requisitos de SO para os binários ELF legados 32-bit do GameServer.
# Idempotente. NÃO purga pacotes.
#
# Cobre 100% dos achados de runtime do docs/server-files-notes.md §"ACHADOS DE
# EXECUÇÃO REAL" #3 + #4:
#   - locale C (loadlocale.c abort sem isto)
#   - libs i386 (libc6, libstdc++6, libgcc-s1, zlib1g)
#   - nscd ativo (SIGSEGV em getaddrinfo sem socket /var/run/nscd/socket)
#   - hosts: files dns em /etc/nsswitch.conf
#
# Persiste o locale em /etc/default/locale (não só Environment= das units),
# para shells interativos e diagnóstico (psql, journalctl, etc).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root

log "[10-os] update + i386"
apt-get update -y
if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
  dpkg --add-architecture i386
  apt-get update -y
fi

log "[10-os] libs 32-bit + nscd + locales + utilitários"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386 \
  nscd locales ca-certificates curl gnupg lsb-release rsync

log "[10-os] locale C (persistente)"
if ! locale -a | grep -qiE '^C(\..+)?$'; then
  locale-gen C
fi
# Persiste no SO inteiro — Environment= das units já cobre cada serviço,
# mas isto cobre o shell interativo, cron, e diagnóstico.
cat > /etc/default/locale <<'EOF'
LANG=C
LC_ALL=C
LANGUAGE=C
EOF

log "[10-os] nscd ativo"
systemctl enable --now nscd

log "[10-os] nsswitch (hosts: files dns)"
if ! grep -qE '^hosts:\s*files\s+dns' /etc/nsswitch.conf; then
  cp -a /etc/nsswitch.conf /etc/nsswitch.conf.bak.gf-ops 2>/dev/null || true
  sed -i.tmp -E 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
  rm -f /etc/nsswitch.conf.tmp
fi

log "[10-os] OK"
