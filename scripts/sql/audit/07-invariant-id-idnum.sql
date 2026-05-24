-- 07-invariant-id-idnum.sql — sentinela da invariante #1 do CLAUDE.md §6.
--
-- Cross-DB: requer extensão dblink em gf_ls.
--   sudo -u postgres psql -d gf_ls -c 'CREATE EXTENSION IF NOT EXISTS dblink;'
--
-- Banco: gf_ls. Rode com:  psql -d gf_ls -f 07-invariant-id-idnum.sql
--
-- Se NÃO quiser instalar dblink, o run-audit.sh tem um caminho alternativo que
-- faz duas dumps + diff em bash (escala bem para milhares de contas, e não
-- adiciona extensão ao cluster). Aqui é a versão SQL pura.

\echo === contas com id != idnum (RESULTADO ESPERADO: 0 linhas) ===
SELECT a.id AS ls_id, a.username, ms.idnum AS ms_idnum
FROM accounts a
LEFT JOIN dblink('dbname=gf_ms',
                 'SELECT mid, idnum FROM tb_user')
       AS ms(mid varchar, idnum bigint)
  ON ms.mid = a.username
WHERE ms.idnum IS NULL OR ms.idnum != a.id
LIMIT 100;
