-- 06-gm-privilege.sql — todos os privilégios de GM atualmente atribuídos.
-- ATENÇÃO: este script toca 3 bancos. Use o wrapper run-audit.sh ou rode em 3 passos:
--   psql -d gf_gs -f 06-gm-privilege.sql      (parte 1)
--   psql -d gf_ls -f 06-gm-privilege.sql      (parte 2)
--   psql -d gf_ms -f 06-gm-privilege.sql      (parte 3)
-- Cada \echo abaixo é guardado por um SELECT current_database() pra ficar claro.
--
-- Bug do painel original: gravava em gf_ls.gm_tool_account (singular) em vez de
-- gm_tool_accounts (plural). O painel reescrito corrige; esta query revela
-- inconsistências históricas: char com privilege=5 sem entrada em gm_tool_accounts,
-- ou tb_user.byauthority=5 sem char correspondente, etc.

\echo === parte 1 (rode em gf_gs): GMs por personagem ===
SELECT account_id, id, given_name, privilege
FROM player_characters
WHERE privilege = 5
ORDER BY account_id, id;

\echo
\echo === parte 2 (rode em gf_ls): tabela gm_tool_accounts ===
SELECT id AS account_id, account_name, privilege
FROM gm_tool_accounts
WHERE privilege = 5
ORDER BY id;

\echo
\echo === parte 2b (rode em gf_ls): tabela LEGADA singular (se existir) ===
-- Se este SELECT der erro 'relation does not exist' é BOM — significa que ninguém
-- mais escreve na tabela errada. Se trouxer linhas, o painel original ainda está em uso.
SELECT 'tabela singular ainda em uso (limpe via UPDATE/DROP)' AS warn
WHERE EXISTS (SELECT 1 FROM information_schema.tables
              WHERE table_schema='public' AND table_name='gm_tool_account');

\echo
\echo === parte 3 (rode em gf_ms): tb_user.byauthority ===
SELECT mid, idnum, byauthority
FROM tb_user
WHERE byauthority >= 5
ORDER BY idnum;
