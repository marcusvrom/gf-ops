<?php
declare(strict_types=1);

// PDO com prepared statements reais (emulação desligada).
// Uma instância por banco; mantida no contêiner global $DB.

function gf_pdo(string $dbname): PDO {
    global $CONFIG, $DB;
    if (isset($DB[$dbname])) {
        return $DB[$dbname];
    }
    $c = $CONFIG['db'];
    $dsn = sprintf(
        'pgsql:host=%s;port=%s;dbname=%s;options=--client_encoding=UTF8',
        $c['host'], $c['port'], $dbname
    );
    $pdo = new PDO($dsn, $c['user'], $c['password'], [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false, // server-side prepares de verdade
    ]);
    $DB[$dbname] = $pdo;
    return $pdo;
}

function gf_ls(): PDO { return gf_pdo('gf_ls'); }
function gf_gs(): PDO { return gf_pdo('gf_gs'); }
function gf_ms(): PDO { return gf_pdo('gf_ms'); }
