-- 02-grants-gf_gs.sql — GRANTs no banco gf_gs.
-- Rode com:  sudo -u postgres psql -v ON_ERROR_STOP=1 -d gf_gs -f 02-grants-gf_gs.sql
--
-- Idempotente: GRANT é aditivo; REVOKE FROM PUBLIC é safe re-rodar.

-- 1) Limpa privilégios do role PUBLIC (qualquer login conectado ganharia esses
--    por default). Não afeta gf_game/gf_panel que já receberão GRANTs explícitos.
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- 2) USAGE no schema (sem isso, nem dá pra resolver os nomes das tabelas).
GRANT USAGE ON SCHEMA public TO gf_game, gf_panel;

-- 3) gf_game — RW completo. "Amplo por necessidade": os binários do servidor
--    são caixa-preta; tocam praticamente toda a centena+ de tabelas do gf_gs
--    (player_characters, bags, auction, storage, mailitem, family*, isle*, etc).
--    Não dá pra recortar com segurança sem traçar o I/O de cada um.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO gf_game;
GRANT USAGE,  SELECT, UPDATE         ON ALL SEQUENCES IN SCHEMA public TO gf_game;

-- ALTER DEFAULT PRIVILEGES FOR ROLE postgres: cobre objetos criados por updates
-- futuros do schema (que rodam como postgres via psql_super). Sem isso, qualquer
-- tabela nova entraria sem GRANT e o jogo quebraria silenciosamente.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO gf_game;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT USAGE,  SELECT, UPDATE         ON SEQUENCES TO gf_game;

-- 4) gf_panel — "Mínimo por auditoria". Só o que o web/ realmente toca.
--    Auditoria das chamadas em web/lib/accounts.php + web/public/admin/*.php:
--      - player_characters: SELECT (characters, gm) + UPDATE (gm, rename)
--      - serverstatus:      SELECT (futuro: status page consumir ext_address/timers)
GRANT SELECT, UPDATE ON TABLE player_characters TO gf_panel;
GRANT SELECT         ON TABLE serverstatus      TO gf_panel;

-- Verificação (informativa)
\echo '== privilégios em gf_gs.player_characters =='
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='player_characters'
  AND grantee IN ('gf_game','gf_panel','PUBLIC')
ORDER BY grantee, privilege_type;
