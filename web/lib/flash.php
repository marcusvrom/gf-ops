<?php
declare(strict_types=1);

function flash_set(string $level, string $msg): void {
    $_SESSION['flash'][] = ['level' => $level, 'msg' => $msg];
}

function flash_render(): string {
    if (empty($_SESSION['flash'])) return '';
    $out = '';
    foreach ($_SESSION['flash'] as $f) {
        $color = $f['level'] === 'ok' ? 'green' : ($f['level'] === 'warn' ? 'orange' : 'red');
        $out .= '<p style="color:' . $color . '">' . h($f['msg']) . '</p>';
    }
    unset($_SESSION['flash']);
    return $out;
}
