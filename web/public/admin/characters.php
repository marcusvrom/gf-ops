<?php
require __DIR__ . '/../../lib/bootstrap.php';
require __DIR__ . '/../_layout.php';
require_admin();

$ls = gf_ls();
$gs = gf_gs();

$accounts = $ls->query('SELECT id, username FROM accounts ORDER BY id')->fetchAll();
$charsByAccount = [];
$st = $gs->prepare('SELECT given_name FROM player_characters WHERE account_id = :a ORDER BY id');
foreach ($accounts as $a) {
    $st->execute([':a' => $a['id']]);
    $charsByAccount[$a['id']] = $st->fetchAll();
}

render_header('Personagens por conta');
foreach ($accounts as $a): ?>
  <table>
    <tr><th>Conta #<?= (int)$a['id'] ?></th><th><?= h($a['username']) ?></th></tr>
    <?php $n = 1; foreach ($charsByAccount[$a['id']] as $c): ?>
      <tr><td>Personagem <?= $n++ ?></td><td><?= h($c['given_name']) ?></td></tr>
    <?php endforeach ?>
  </table>
<?php endforeach;
render_footer();
