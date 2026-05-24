<?php
require __DIR__ . '/../lib/bootstrap.php';
require __DIR__ . '/_layout.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $u = trim((string)($_POST['username'] ?? ''));
    $p = (string)($_POST['password'] ?? '');
    if (panel_login($u, $p)) {
        header('Location: /admin/characters.php'); exit;
    }
    flash_set('err', 'Credenciais inválidas.');
    header('Location: /login.php'); exit;
}

render_header('Admin · Login');
?>
<form method="post">
  <?= csrf_field() ?>
  <p><label>Usuário</label><input type="text" name="username" required autofocus></p>
  <p><label>Senha</label><input type="password" name="password" required></p>
  <p><button type="submit">Entrar</button></p>
</form>
<p><small>Crie o primeiro admin via <code>php bin/create-admin.php &lt;user&gt; &lt;senha&gt;</code>.</small></p>
<?php render_footer();
