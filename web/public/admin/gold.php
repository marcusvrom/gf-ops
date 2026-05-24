<?php
require __DIR__ . '/../../lib/bootstrap.php';
require __DIR__ . '/../_layout.php';
require_admin();

const AP_HARD_CAP = 99999; // teto absoluto do campo pvalues (limite legado do painel original)

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $user   = trim((string)($_POST['username'] ?? ''));
    $amount = filter_input(INPUT_POST, 'amount', FILTER_VALIDATE_INT, [
        'options' => ['min_range' => 1, 'max_range' => AP_HARD_CAP]
    ]);

    if ($user === '' || $amount === false || $amount === null) {
        flash_set('err', 'Username e valor (1..' . AP_HARD_CAP . ') são obrigatórios.');
        header('Location: /admin/gold.php'); exit;
    }

    $ms = gf_ms();
    $ms->beginTransaction();
    try {
        // SELECT FOR UPDATE evita race com outro admin somando ao mesmo tempo.
        $st = $ms->prepare('SELECT pvalues FROM tb_user WHERE mid = :u FOR UPDATE');
        $st->execute([':u' => $user]);
        $row = $st->fetch();
        if (!$row) {
            $ms->rollBack();
            flash_set('err', "Conta '{$user}' não encontrada.");
        } else {
            $current = (int)$row['pvalues'];
            $new = $current + $amount;
            if ($new > AP_HARD_CAP) {
                $ms->rollBack();
                flash_set('err', "Valor resultante {$new} excede o teto " . AP_HARD_CAP . " (atual: {$current}).");
            } else {
                $up = $ms->prepare('UPDATE tb_user SET pvalues = :v WHERE mid = :u');
                $up->execute([':v' => $new, ':u' => $user]);
                $ms->commit();
                error_log("[panel:gold] admin=" . admin_user() . " user={$user} +{$amount} -> {$new}");
                flash_set('ok', "AP de '{$user}': {$current} → {$new}.");
            }
        }
    } catch (Throwable $e) {
        if ($ms->inTransaction()) $ms->rollBack();
        error_log('[panel:gold] ' . $e->getMessage());
        flash_set('err', 'Erro interno.');
    }
    header('Location: /admin/gold.php'); exit;
}

render_header('Adicionar AP');
?>
<form method="post">
  <?= csrf_field() ?>
  <p><label>Conta (mid)</label><input type="text" name="username" required></p>
  <p><label>Valor a somar</label><input type="number" name="amount" min="1" max="<?= AP_HARD_CAP ?>" required></p>
  <p><button type="submit">Adicionar AP</button></p>
</form>
<p><small>Teto absoluto por conta: <?= AP_HARD_CAP ?>.</small></p>
<?php render_footer();
