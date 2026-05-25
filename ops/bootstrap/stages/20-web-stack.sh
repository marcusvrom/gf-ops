#!/usr/bin/env bash
# stage 20 — Apache + PHP com as extensões necessárias.
#
# Cobre achados de runtime + o que NÃO estava em código antes:
#   - php-pgsql   (PDO_pgsql usado em web/lib/db.php)
#   - php-mbstring (mb_strlen em index.php / admin/change.php / admin/index.php —
#                   sem isso, REGISTRO de jogador quebra silenciosamente com
#                   "Call to undefined function mb_strlen()". Foi a lacuna que
#                   este stage existe para preencher.)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib.sh"
require_root

log "[20-web] apache2 + php + extensões"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 php php-cli libapache2-mod-php \
  php-pgsql \
  php-mbstring

systemctl enable --now apache2

log "[20-web] OK — extensões PHP confirmadas:"
php -m | grep -E '^(pgsql|mbstring|pdo_pgsql|PDO)$' | sort -u
