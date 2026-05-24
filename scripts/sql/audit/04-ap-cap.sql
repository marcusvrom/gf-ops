-- 04-ap-cap.sql — contas com AP (pvalues) no teto 99999.
-- Banco: gf_ms. Rode com:  psql -d gf_ms -f 04-ap-cap.sql
--
-- pvalues é a moeda premium (AP). Teto codificado = 99999 (gold.php legado e painel novo).
-- Alta contagem de contas no teto SEM transações registradas = bug de teto ou injeção.
-- Confronte com os logs do painel (jornal: 'panel:gold').

\echo === contagem no teto ===
SELECT
  COUNT(*) FILTER (WHERE pvalues = 99999) AS no_teto,
  COUNT(*) FILTER (WHERE pvalues > 0 AND pvalues < 99999) AS positivo_abaixo_do_teto,
  COUNT(*) FILTER (WHERE pvalues = 0) AS zerado,
  COUNT(*) FILTER (WHERE pvalues > 99999) AS ACIMA_DO_TETO_INVESTIGAR,
  COUNT(*) AS total
FROM tb_user;

\echo
\echo === contas no teto (lista; use no cross-check com auditoria do painel) ===
SELECT mid, idnum, pvalues, byauthority, lastlogindate
FROM tb_user
WHERE pvalues = 99999
ORDER BY lastlogindate DESC NULLS LAST
LIMIT 100;

\echo
\echo === contas ACIMA do teto (bug ou injeção direta no banco) ===
SELECT mid, idnum, pvalues, byauthority
FROM tb_user
WHERE pvalues > 99999;
