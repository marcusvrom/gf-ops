<?php
// Mini-layout. Páginas chamam render_header()/render_footer().
function render_header(string $title): void { ?>
<!doctype html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<title>GF | <?= h($title) ?></title>
<style>
  body{font-family:system-ui,sans-serif;max-width:720px;margin:2em auto;padding:0 1em}
  nav a{margin-right:1em}
  form{margin:1em 0}
  label{display:inline-block;min-width:9em}
  input[type=text],input[type=password],input[type=number]{padding:.3em;min-width:14em}
  table{border-collapse:collapse;margin:1em 0;min-width:280px}
  th,td{border:1px solid #999;padding:.4em .6em}
  th{background:#eee}
  .topbar{font-size:.9em;color:#555}
</style>
</head>
<body>
<div class="topbar">
  <?php if (admin_user()): ?>
    Logado como <strong><?= h(admin_user()) ?></strong>
    · <a href="/logout.php">sair</a>
  <?php endif ?>
</div>
<nav>
  <a href="/">Registro</a>
  <a href="/status.php">Status</a>
  <?php if (admin_user()): ?>
    <a href="/admin/characters.php">Personagens</a>
    <a href="/admin/gold.php">AP</a>
    <a href="/admin/gm.php">GM</a>
    <a href="/admin/change.php">Renomear</a>
  <?php else: ?>
    <a href="/login.php">Admin</a>
  <?php endif ?>
</nav>
<h2><?= h($title) ?></h2>
<?= flash_render() ?>
<?php }

function render_footer(): void { ?>
</body></html>
<?php }
