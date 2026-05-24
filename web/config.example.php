<?php
// Copie para config.local.php e ajuste. config.local.php é gitignored.
// Em produção, prefira variáveis de ambiente (getenv) em vez de hardcode.

return [
    'db' => [
        'host'     => getenv('GF_DB_HOST')     ?: '127.0.0.1',
        'port'     => getenv('GF_DB_PORT')     ?: '5432',
        'user'     => getenv('GF_DB_USER')     ?: 'postgres',   // TODO hardening: role dedicada
        'password' => getenv('GF_DB_PASSWORD') ?: 'CHANGEME',
    ],

    // Portas usadas pelo status.php (fsockopen).
    'server' => [
        'host'         => getenv('GF_SERVER_HOST') ?: '127.0.0.1',
        'login_port'   => 6543,
        'gateway_port' => 5560,
        'ticket_port'  => 7777,
    ],

    // Sessão. Em produção atrás de HTTPS, defina cookie_secure=true.
    'session' => [
        'name'          => 'gfpanel',
        'cookie_secure' => filter_var(getenv('GF_COOKIE_SECURE') ?: 'false', FILTER_VALIDATE_BOOLEAN),
        'cookie_samesite' => 'Lax',
        'idle_timeout'  => 1800, // segundos
    ],

    // Política de registro público. Em rede aberta, considere desabilitar
    // (registro só via painel admin) ou exigir captcha externo.
    'registration' => [
        'enabled'      => filter_var(getenv('GF_REGISTRATION_ENABLED') ?: 'true', FILTER_VALIDATE_BOOLEAN),
        'min_user_len' => 4,
        'max_user_len' => 20,
        'min_pass_len' => 6,
        // Regex de username: alfanumérico + underscore. Evita injeção e batidas com tokens do client.
        'user_regex'   => '/^[A-Za-z0-9_]+$/',
    ],
];
