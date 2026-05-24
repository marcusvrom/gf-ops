<?php
declare(strict_types=1);

// Lógica atômica de criação de conta — equivalente PHP do scripts/setup/create_account.sh.
//
// Invariantes (CLAUDE.md §6):
//   1. gf_ls.accounts.id == gf_ms.tb_user.idnum (mesma PK lógica em 2 bancos sem FK)
//   2. password = md5(senha) em accounts.password, tb_user.password e tb_user.pwd
//   3. ID gerado por SEQUENCE dedicada (account_id_seq_mvp), não por MAX(id)+1
//   4. Cross-DB: se a inserção em gf_ms falhar, desfazer a de gf_ls
//
// O painel reescrito é o ÚNICO caminho que deve criar conta a partir daqui em diante.
// O script .sh continua válido para operação fora do painel; ambos compartilham a
// mesma sequence em gf_ls (account_id_seq_mvp).

class AccountException extends RuntimeException {}

/**
 * Cria conta nos dois bancos, atomicamente.
 *
 * @param bool $isGm Eleva byauthority=5 em gf_ms.tb_user (para criação por admin).
 * @return int Novo account id (== idnum).
 * @throws AccountException
 */
function create_account(string $username, string $passwordRaw, bool $isGm = false): int {
    $ls = gf_ls();
    $ms = gf_ms();

    // Pré-checagem: username já existe?
    $st = $ls->prepare('SELECT 1 FROM accounts WHERE username = :u');
    $st->execute([':u' => $username]);
    if ($st->fetchColumn()) {
        throw new AccountException("Username '{$username}' já existe.");
    }

    $passMd5 = md5($passwordRaw);
    $auth    = $isGm ? 5 : 0;

    // Garante a sequence dedicada (idempotente). Reproduz o DO $$ ... $$ do .sh.
    // Não há "CREATE SEQUENCE IF NOT EXISTS" antes do PG 9.5; este servidor é PG 13, então existe,
    // mas mantemos a checagem por catalog para sermos defensivos.
    $ls->exec(<<<'SQL'
        DO $$
        DECLARE maxid bigint;
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='S' AND relname='account_id_seq_mvp') THEN
            SELECT COALESCE(MAX(id),0) INTO maxid FROM accounts;
            EXECUTE format('CREATE SEQUENCE account_id_seq_mvp START WITH %s', maxid + 1);
          END IF;
        END $$;
    SQL);

    // ID atômico — independente de MAX(id)+1 (resolve race do painel original).
    $newId = (int)$ls->query("SELECT nextval('account_id_seq_mvp')")->fetchColumn();

    // INSERT 1: gf_ls.accounts. Transação local para podermos desfazer se gf_ms falhar.
    $ls->beginTransaction();
    try {
        $ins = $ls->prepare(
            'INSERT INTO accounts (id, username, password, realname, worldserver,
                                   use_charpassword, state, char_max_num, win_os_bit)
             VALUES (:id, :u, :p, :u, 0, false, 0, 3, 0)'
        );
        $ins->execute([':id' => $newId, ':u' => $username, ':p' => $passMd5]);
    } catch (Throwable $e) {
        $ls->rollBack();
        throw new AccountException('Falha ao inserir em gf_ls.accounts: ' . $e->getMessage(), 0, $e);
    }

    // INSERT 2: gf_ms.tb_user — usa o MESMO id. Se falhar, rollback do gf_ls.
    try {
        $ms->beginTransaction();
        $ins = $ms->prepare(
            'INSERT INTO tb_user (mid, password, pwd, idnum, byauthority,
                                  pvalues, billingrule, status, bonus)
             VALUES (:u, :p, :p, :id, :auth, 99999, 0, 0, 0)'
        );
        $ins->execute([
            ':u' => $username, ':p' => $passMd5,
            ':id' => $newId,   ':auth' => $auth,
        ]);
        $ms->commit();
    } catch (Throwable $e) {
        if ($ms->inTransaction()) { $ms->rollBack(); }
        $ls->rollBack();
        throw new AccountException('Falha ao inserir em gf_ms.tb_user (gf_ls revertido): ' . $e->getMessage(), 0, $e);
    }

    $ls->commit();

    // Verificação final da invariante id==idnum. Se quebrar aqui, alguém mexeu por fora.
    $lsId = (int)pdo_fetch_one($ls, 'SELECT id FROM accounts WHERE username = :u',   [':u' => $username]);
    $msId = (int)pdo_fetch_one($ms, 'SELECT idnum FROM tb_user WHERE mid = :u',      [':u' => $username]);
    if ($lsId !== $msId || $lsId !== $newId) {
        throw new AccountException("Invariante violada: ls.id={$lsId}, ms.idnum={$msId}, esperado={$newId}");
    }

    return $newId;
}

function pdo_fetch_one(PDO $pdo, string $sql, array $params) {
    $st = $pdo->prepare($sql);
    $st->execute($params);
    $v = $st->fetchColumn();
    return $v === false ? null : $v;
}
