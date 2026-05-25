-- 01-roles.sql — cria/atualiza as roles gf_game e gf_panel (idempotente).
--
-- Rode como superuser via wrapper run-hardening.sh (ele injeta as senhas
-- como custom GUCs antes de chamar este arquivo). Uso direto:
--   psql -v game_pwd='...' -v panel_pwd='...' -f 01-roles.sql
--
-- DECISÃO: password_encryption = 'md5'.
-- Os binários ELF do GameServer são da era ~2006/2008 e usam libpq pré-SCRAM
-- (SCRAM só veio em PG10/2017). Se o role for criado com o default do PG13
-- (scram-sha-256), o jogo NÃO consegue autenticar mesmo que pg_hba aceite 'md5'.
-- Forçamos md5 por sessão antes de CREATE/ALTER ROLE.
-- O painel (PDO pgsql, libpq moderno) lida com md5 sem problema.

SET password_encryption = 'md5';

-- Senhas passadas como GUCs custom (escopo de sessão) pelo runner.
-- Não logam nem aparecem em pg_stat_statements.
SELECT set_config('gf.game_pwd',  :'game_pwd',  false);
SELECT set_config('gf.panel_pwd', :'panel_pwd', false);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gf_game') THEN
    EXECUTE format(
      'CREATE ROLE gf_game LOGIN PASSWORD %L
         NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT',
      current_setting('gf.game_pwd')
    );
  ELSE
    EXECUTE format(
      'ALTER ROLE gf_game WITH LOGIN PASSWORD %L
         NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT',
      current_setting('gf.game_pwd')
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gf_panel') THEN
    EXECUTE format(
      'CREATE ROLE gf_panel LOGIN PASSWORD %L
         NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT',
      current_setting('gf.panel_pwd')
    );
  ELSE
    EXECUTE format(
      'ALTER ROLE gf_panel WITH LOGIN PASSWORD %L
         NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT',
      current_setting('gf.panel_pwd')
    );
  END IF;
END $$;

-- Verificação: as roles existem e NÃO são superuser.
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolinherit, rolcanlogin
FROM pg_roles
WHERE rolname IN ('gf_game', 'gf_panel')
ORDER BY rolname;
