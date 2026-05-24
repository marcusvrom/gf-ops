<?php
require __DIR__ . '/../lib/bootstrap.php';
require __DIR__ . '/_layout.php';

$reg = $CONFIG['registration'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();

    $u = trim((string)($_POST['username'] ?? ''));
    $p = (string)($_POST['password'] ?? '');

    $errors = [];
    if (!$reg['enabled']) {
        $errors[] = 'Registro público está desabilitado.';
    }
    $ul = mb_strlen($u);
    if ($ul < $reg['min_user_len'] || $ul > $reg['max_user_len']) {
        $errors[] = "Username deve ter entre {$reg['min_user_len']} e {$reg['max_user_len']} caracteres.";
    }
    if (!preg_match($reg['user_regex'], $u)) {
        $errors[] = 'Username só pode conter letras, números e underscore.';
    }
    if (mb_strlen($p) < $reg['min_pass_len']) {
        $errors[] = "Senha deve ter pelo menos {$reg['min_pass_len']} caracteres.";
    }

    if (!$errors) {
        try {
            $id = create_account($u, $p, false);
            flash_set('ok', "Conta '{$u}' criada (id={$id}). Já pode logar no jogo.");
            header('Location: /'); exit;
        } catch (AccountException $e) {
            $errors[] = $e->getMessage();
        } catch (Throwable $e) {
            error_log('[register] ' . $e->getMessage());
            $errors[] = 'Erro interno ao criar conta.';
        }
    }

    foreach ($errors as $err) flash_set('err', $err);
    header('Location: /'); exit;
}

render_header('Registro');
?>
<form method="post">
  <?= csrf_field() ?>
  <p><label>Username</label><input type="text" name="username" required></p>
  <p><label>Senha</label><input type="password" name="password" required></p>
  <p><button type="submit">Criar conta</button></p>
</form>
<?php render_footer();
