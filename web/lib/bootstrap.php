<?php
declare(strict_types=1);

// Bootstrap: carrega config, abre sessão, expõe helpers.
// Inclua este arquivo no topo de toda página do painel.

$configPath = __DIR__ . '/../config.local.php';
if (!file_exists($configPath)) {
    http_response_code(500);
    exit('config.local.php não encontrado. Copie config.example.php e ajuste.');
}
$CONFIG = require $configPath;

// Erros: não vazar para o cliente. Logar para o stderr do servidor.
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/csrf.php';
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/flash.php';
require_once __DIR__ . '/accounts.php';

// Sessão única, parâmetros endurecidos.
$sess = $CONFIG['session'];
session_name($sess['name']);
session_set_cookie_params([
    'lifetime' => 0,
    'path'     => '/',
    'secure'   => $sess['cookie_secure'],
    'httponly' => true,
    'samesite' => $sess['cookie_samesite'],
]);
session_start();

// Timeout por inatividade.
$now = time();
if (isset($_SESSION['last_activity']) && ($now - $_SESSION['last_activity']) > $sess['idle_timeout']) {
    $_SESSION = [];
    session_destroy();
    session_start();
}
$_SESSION['last_activity'] = $now;

function h(string $s): string {
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
