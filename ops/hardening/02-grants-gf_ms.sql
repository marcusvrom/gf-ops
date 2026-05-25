-- 02-grants-gf_ms.sql — GRANTs no banco gf_ms.
-- Rode com:  sudo -u postgres psql -v ON_ERROR_STOP=1 -d gf_ms -f 02-grants-gf_ms.sql

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT  USAGE ON SCHEMA public TO gf_game, gf_panel;

-- gf_game — RW completo.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO gf_game;
GRANT USAGE,  SELECT, UPDATE         ON ALL SEQUENCES IN SCHEMA public TO gf_game;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO gf_game;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT USAGE,  SELECT, UPDATE         ON SEQUENCES TO gf_game;

-- gf_panel — só tb_user, e SEM DELETE.
--   tb_user: SELECT (login do painel + admin/characters), INSERT (create_account),
--            UPDATE (admin/gold add AP, admin/gm byauthority).
--   Sem DELETE: o painel nunca remove conta. Se o create_account.php rollback
--   acontecer, ele falha NO INSERT do gf_ms (antes do commit) e o gf_ls é
--   desfeito; não chega a precisar de DELETE em gf_ms.
GRANT SELECT, INSERT, UPDATE ON TABLE tb_user TO gf_panel;

\echo '== privilégios em gf_ms.tb_user =='
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='tb_user'
  AND grantee IN ('gf_game','gf_panel','PUBLIC')
ORDER BY grantee, privilege_type;
