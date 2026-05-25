-- 02-grants-gf_ls.sql — GRANTs no banco gf_ls.
-- Rode com:  sudo -u postgres psql -v ON_ERROR_STOP=1 -d gf_ls -f 02-grants-gf_ls.sql

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT  USAGE ON SCHEMA public TO gf_game, gf_panel;

-- gf_game — RW completo (mesmo raciocínio do gf_gs: binário caixa-preta).
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO gf_game;
GRANT USAGE,  SELECT, UPDATE         ON ALL SEQUENCES IN SCHEMA public TO gf_game;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO gf_game;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT USAGE,  SELECT, UPDATE         ON SEQUENCES TO gf_game;

-- gf_panel — mínimo conforme auditoria das chamadas do web/:
--   accounts          : SELECT + INSERT + UPDATE + DELETE
--                       (DELETE é necessário para o rollback cross-DB do create_account
--                        em web/lib/accounts.php, quando o INSERT em gf_ms.tb_user falha.)
--   gm_tool_accounts  : SELECT + INSERT + UPDATE (admin/gm.php upsert manual)
--   panel_admins      : SELECT + INSERT + UPDATE (login + bin/create-admin.php)
--   worlds            : SELECT (status do mundo no painel futuro)
--   account_id_seq_mvp: USAGE + SELECT + UPDATE (nextval) — sequence atômica do create_account
--   panel_admins_id_seq: USAGE + SELECT + UPDATE (serial da panel_admins)
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE accounts          TO gf_panel;
GRANT SELECT, INSERT, UPDATE         ON TABLE gm_tool_accounts  TO gf_panel;
GRANT SELECT, INSERT, UPDATE         ON TABLE panel_admins      TO gf_panel;
GRANT SELECT                         ON TABLE worlds            TO gf_panel;

GRANT USAGE, SELECT, UPDATE ON SEQUENCE account_id_seq_mvp      TO gf_panel;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE panel_admins_id_seq     TO gf_panel;

\echo '== privilégios em gf_ls.accounts =='
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='accounts'
  AND grantee IN ('gf_game','gf_panel','PUBLIC')
ORDER BY grantee, privilege_type;
