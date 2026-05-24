<?php
require __DIR__ . '/../../lib/bootstrap.php';
require __DIR__ . '/../_layout.php';
require_admin();

const NAME_MIN = 4;
const NAME_MAX = 16;
const NAME_REGEX = '/^[A-Za-z0-9_]+$/'; // sem espaço, sem caractere especial

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $old = trim((string)($_POST['oldname'] ?? ''));
    $new = trim((string)($_POST['newname'] ?? ''));

    $errors = [];
    if ($old === '')                                $errors[] = 'Nome atual obrigatório.';
    $nl = mb_strlen($new);
    if ($nl < NAME_MIN || $nl > NAME_MAX)           $errors[] = 'Novo nome: ' . NAME_MIN . '..' . NAME_MAX . ' caracteres.';
    if (!preg_match(NAME_REGEX, $new))              $errors[] = 'Novo nome: somente letras, números, underscore.';
    if ($old === $new && !$errors)                  $errors[] = 'O novo nome é igual ao atual.';

    if (!$errors) {
        $gs = gf_gs();
        $gs->beginTransaction();
        try {
            // Travamos a linha do antigo + checamos colisão dentro da mesma transação.
            $st = $gs->prepare('SELECT id FROM player_characters WHERE given_name = :n FOR UPDATE');
            $st->execute([':n' => $old]);
            if (!$st->fetchColumn()) {
                $gs->rollBack();
                $errors[] = "Personagem '{$old}' não encontrado.";
            } else {
                $st = $gs->prepare('SELECT 1 FROM player_characters WHERE given_name = :n');
                $st->execute([':n' => $new]);
                if ($st->fetchColumn()) {
                    $gs->rollBack();
                    $errors[] = "Já existe personagem '{$new}'.";
                } else {
                    $up = $gs->prepare('UPDATE player_characters SET given_name = :new WHERE given_name = :old');
                    $up->execute([':new' => $new, ':old' => $old]);
                    $gs->commit();
                    error_log("[panel:rename] admin=" . admin_user() . " {$old} -> {$new}");
                    flash_set('ok', "Renomeado '{$old}' → '{$new}'.");
                }
            }
        } catch (Throwable $e) {
            if ($gs->inTransaction()) $gs->rollBack();
            error_log('[panel:rename] ' . $e->getMessage());
            $errors[] = 'Erro interno.';
        }
    }

    foreach ($errors as $err) flash_set('err', $err);
    header('Location: /admin/change.php'); exit;
}

render_header('Renomear personagem');
?>
<form method="post">
  <?= csrf_field() ?>
  <p><label>Nome atual</label><input type="text" name="oldname" required></p>
  <p><label>Novo nome</label><input type="text" name="newname" required minlength="<?= NAME_MIN ?>" maxlength="<?= NAME_MAX ?>"></p>
  <p><button type="submit">Renomear</button></p>
</form>
<?php render_footer();
