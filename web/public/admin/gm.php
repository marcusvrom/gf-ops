<?php
require __DIR__ . '/../../lib/bootstrap.php';
require __DIR__ . '/../_layout.php';
require_admin();

// Aplica privilégio nos 3 lugares esperados pelo servidor (CLAUDE.md / server-files-notes.md §schema):
//   - gf_gs.player_characters.privilege   (5 = GM, 0 = normal)  para TODOS os chars da conta
//   - gf_ls.gm_tool_accounts (id, account_name, password, privilege)  -> usa o PLURAL correto
//     (o painel original tinha bug com 'gm_tool_account' singular no UPDATE)
//   - gf_ms.tb_user.byauthority

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $player = trim((string)($_POST['playername'] ?? ''));
    $action = $_POST['action'] ?? '';
    $privilege = $action === 'add' ? 5 : 0;

    if ($player === '' || !in_array($action, ['add', 'remove'], true)) {
        flash_set('err', 'Player e ação obrigatórios.');
        header('Location: /admin/gm.php'); exit;
    }

    $gs = gf_gs();
    $ls = gf_ls();
    $ms = gf_ms();

    try {
        // Localiza account_id a partir do nome do personagem.
        $st = $gs->prepare('SELECT account_id FROM player_characters WHERE given_name = :n LIMIT 1');
        $st->execute([':n' => $player]);
        $accountId = $st->fetchColumn();
        if (!$accountId) {
            flash_set('err', "Personagem '{$player}' não encontrado.");
            header('Location: /admin/gm.php'); exit;
        }
        $accountId = (int)$accountId;

        // Username correspondente.
        $username = pdo_fetch_one($ls, 'SELECT username FROM accounts WHERE id = :id', [':id' => $accountId]);
        if (!$username) {
            flash_set('err', "Conta {$accountId} não encontrada em gf_ls.");
            header('Location: /admin/gm.php'); exit;
        }

        // gf_gs.player_characters.privilege para todos os personagens da conta.
        $up = $gs->prepare('UPDATE player_characters SET privilege = :p WHERE account_id = :a');
        $up->execute([':p' => $privilege, ':a' => $accountId]);

        // gf_ls.gm_tool_accounts (upsert manual: existe? UPDATE; senão INSERT).
        $exists = pdo_fetch_one($ls, 'SELECT 1 FROM gm_tool_accounts WHERE id = :id', [':id' => $accountId]);
        if ($exists) {
            $up = $ls->prepare('UPDATE gm_tool_accounts SET privilege = :p WHERE id = :id');
            $up->execute([':p' => $privilege, ':id' => $accountId]);
        } else {
            // Reusa username/password legado (MD5) — a tabela carrega cópia do hash da conta.
            $pwd = pdo_fetch_one($ls, 'SELECT password FROM accounts WHERE id = :id', [':id' => $accountId]);
            $ins = $ls->prepare(
                'INSERT INTO gm_tool_accounts (id, account_name, password, privilege)
                 VALUES (:id, :u, :p, :priv)'
            );
            $ins->execute([':id' => $accountId, ':u' => $username, ':p' => $pwd, ':priv' => $privilege]);
        }

        // gf_ms.tb_user.byauthority.
        $up = $ms->prepare('UPDATE tb_user SET byauthority = :p WHERE mid = :u');
        $up->execute([':p' => $privilege, ':u' => $username]);

        error_log("[panel:gm] admin=" . admin_user() . " player={$player} account={$accountId} -> {$privilege}");
        flash_set('ok', "Privilégio de '{$player}' (conta {$username}) alterado para {$privilege}.");
    } catch (Throwable $e) {
        error_log('[panel:gm] ' . $e->getMessage());
        flash_set('err', 'Erro ao aplicar privilégio.');
    }
    header('Location: /admin/gm.php'); exit;
}

render_header('GM · Alterar privilégio');
?>
<form method="post">
  <?= csrf_field() ?>
  <p><label>Personagem</label><input type="text" name="playername" required></p>
  <p>
    <label>Ação</label>
    <select name="action">
      <option value="add">Promover a GM (5)</option>
      <option value="remove">Remover GM (0)</option>
    </select>
  </p>
  <p><button type="submit">Aplicar</button></p>
</form>
<p><small>Aplica em gf_gs.player_characters, gf_ls.gm_tool_accounts e gf_ms.tb_user.byauthority.</small></p>
<?php render_footer();
