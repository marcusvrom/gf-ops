#!/usr/bin/env bash
# Deploy do painel REESCRITO (web/) em /var/www/gf-panel, vhost Apache.
# Substitui o /var/www/html/*.php legado (SQLi em todos os endpoints).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_root
load_env

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_WEB="${REPO_ROOT}/web"
DST_WEB="/var/www/gf-panel"
PANEL_HOST="${GF_PANEL_SERVER_NAME:-gf-panel.local}"

[[ -d "$SRC_WEB" ]] || die "não encontrado: $SRC_WEB"

log "instalando apache2 + php-pgsql"
DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-cli php-pgsql libapache2-mod-php

log "desativando default site (porta 80) p/ não conflitar"
a2dissite 000-default >/dev/null 2>&1 || true

log "removendo /var/www/html/*.php legado (SQLi)"
# Mantém /var/www/html como dir (mod_dir pode reclamar se sumir), só limpa o painel velho.
rm -f /var/www/html/index.html /var/www/html/*.php

log "sincronizando ${SRC_WEB} -> ${DST_WEB}"
install -d -m 0755 -o root -g root "$DST_WEB"
rsync -a --delete --exclude config.local.php --exclude .gitignore "${SRC_WEB}/" "${DST_WEB}/"

log "renderizando ${DST_WEB}/config.local.php"
# O painel já lê via getenv() com defaults; ainda assim escrevemos config.local.php
# para fixar valores e dispensar SetEnv no vhost.
cat > "${DST_WEB}/config.local.php" <<PHP
<?php
return [
    'db' => [
        'host'     => '${GF_DB_HOST:-127.0.0.1}',
        'port'     => '${GF_DB_PORT:-5432}',
        'user'     => '${GF_DB_USER}',
        'password' => '${GF_DB_PASSWORD}',
    ],
    'server' => [
        'host'         => '${GF_SERVER_HOST_IP}',
        'login_port'   => 6543,
        'gateway_port' => 5560,
        'ticket_port'  => 7777,
    ],
    'session' => [
        'name'            => 'gfpanel',
        'cookie_secure'   => false,
        'cookie_samesite' => 'Lax',
        'idle_timeout'    => 1800,
    ],
    'registration' => [
        'enabled'      => true,
        'min_user_len' => 4,
        'max_user_len' => 20,
        'min_pass_len' => 6,
        'user_regex'   => '/^[A-Za-z0-9_]+\$/',
    ],
];
PHP
chown root:www-data "${DST_WEB}/config.local.php"
chmod 0640         "${DST_WEB}/config.local.php"

log "ajustando ownership / perms do painel"
chown -R root:www-data "$DST_WEB"
find "$DST_WEB" -type d -exec chmod 0750 {} +
find "$DST_WEB" -type f -exec chmod 0640 {} +
chmod 0640 "${DST_WEB}/config.local.php"

log "gerando vhost /etc/apache2/sites-available/gf-panel.conf"
cat > /etc/apache2/sites-available/gf-panel.conf <<APACHE
<VirtualHost *:80>
    ServerName ${PANEL_HOST}
    DocumentRoot ${DST_WEB}/public

    <Directory ${DST_WEB}/public>
        AllowOverride None
        Require all granted
        DirectoryIndex index.php
    </Directory>

    # lib/, migrations/, bin/, config.local.php NÃO ficam expostos:
    # vivem fora do DocumentRoot. Bloqueio explícito caso alguém copie
    # arquivos pra dentro de public/ por engano:
    <FilesMatch "(config\.local\.php|\.env)$">
        Require all denied
    </FilesMatch>

    ErrorLog  \${APACHE_LOG_DIR}/gf-panel.error.log
    CustomLog \${APACHE_LOG_DIR}/gf-panel.access.log combined
</VirtualHost>
APACHE

a2ensite gf-panel >/dev/null
systemctl reload apache2

log "rodando migrations do painel"
sudo -u postgres psql -v ON_ERROR_STOP=1 -f "${DST_WEB}/migrations/001_account_id_seq_mvp.sql"
sudo -u postgres psql -v ON_ERROR_STOP=1 -f "${DST_WEB}/migrations/002_panel_admins.sql"
# A tabela acabou de ser criada como postgres — reasign para gf_app.
psql_super -d gf_ls -c "ALTER TABLE panel_admins OWNER TO ${GF_DB_USER};"
psql_super -d gf_ls -c "ALTER SEQUENCE panel_admins_id_seq OWNER TO ${GF_DB_USER};"

log "OK — painel em http://${PANEL_HOST}/  (DocumentRoot: ${DST_WEB}/public)"
log "    crie o primeiro admin: cd ${DST_WEB} && php bin/create-admin.php <user> <senha>"
