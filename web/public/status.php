<?php
require __DIR__ . '/../lib/bootstrap.php';
require __DIR__ . '/_layout.php';

$srv = $CONFIG['server'];

function probe(string $host, int $port): bool {
    $sock = @fsockopen($host, $port, $errno, $errstr, 1.0);
    if (!$sock) return false;
    fclose($sock);
    return true;
}

$states = [
    'TicketServer'  => probe($srv['host'], $srv['ticket_port']),
    'GatewayServer' => probe($srv['host'], $srv['gateway_port']),
    'LoginServer'   => probe($srv['host'], $srv['login_port']),
];

$accounts = (int)pdo_fetch_one(gf_ls(), 'SELECT count(*) FROM accounts', []);
$chars    = (int)pdo_fetch_one(gf_gs(), 'SELECT count(*) FROM player_characters', []);

$any = in_array(true, $states, true);

render_header('Status');
?>
<p>Status global:
  <strong style="color:<?= $any ? 'green' : 'red' ?>">
    <?= $any ? 'Online' : 'Offline' ?>
  </strong>
</p>
<table>
  <tr><th>Processo</th><th>Estado</th></tr>
  <?php foreach ($states as $name => $up): ?>
    <tr>
      <td><?= h($name) ?></td>
      <td style="color:<?= $up ? 'green' : 'red' ?>">
        <?= $up ? 'Online' : 'Offline' ?>
      </td>
    </tr>
  <?php endforeach ?>
</table>
<p>Contas registradas: <?= $accounts ?></p>
<p>Personagens criados: <?= $chars ?></p>
<?php render_footer();
