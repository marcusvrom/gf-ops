<?php
declare(strict_types=1);

// Auth do PAINEL — independente da senha legada MD5 do jogo.
// Tabela: gf_ls.panel_admins (ver migrations/002_panel_admins.sql).
// Hash: password_hash() (bcrypt) — só para login do painel; nada toca o LoginServer.

function panel_login(string $user, string $password): bool {
    $st = gf_ls()->prepare('SELECT id, username, password_hash FROM panel_admins WHERE username = :u');
    $st->execute([':u' => $user]);
    $row = $st->fetch();
    if (!$row || !password_verify($password, $row['password_hash'])) {
        // sleep curto para mitigar enumeração por timing
        usleep(random_int(100_000, 300_000));
        return false;
    }
    session_regenerate_id(true);
    $_SESSION['admin_id']   = (int)$row['id'];
    $_SESSION['admin_user'] = $row['username'];
    return true;
}

function panel_logout(): void {
    $_SESSION = [];
    session_destroy();
}

function require_admin(): void {
    if (empty($_SESSION['admin_id'])) {
        header('Location: ../login.php');
        exit;
    }
}

function admin_user(): ?string {
    return $_SESSION['admin_user'] ?? null;
}
