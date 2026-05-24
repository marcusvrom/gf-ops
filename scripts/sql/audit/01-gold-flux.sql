-- 01-gold-flux.sql — fluxo diário de gold (criação vs destruição).
-- Banco: gf_gs. Rode com:  psql -d gf_gs -f 01-gold-flux.sql
--
-- gold_log é o agregador diário do servidor (CLAUDE.md / server-files-notes.md):
--   date, increase (gold gerado), decrease (gold destruído), range1..range10 (faixas).
--
-- Saída:
--   1) Últimos 30 dias: increase, decrease, net, e net acumulado.
--   2) Janela de inflação: média(increase) últimos 7d vs 21d anteriores.
--      Razão >= 2.0 sugere inflação anômala (drop massivo, novo bug de dupe).

\echo === gold_flux: últimos 30 dias ===
SELECT
  date,
  increase,
  decrease,
  (increase - decrease)                                  AS net,
  SUM(increase - decrease) OVER (ORDER BY date)          AS net_acum
FROM gold_log
WHERE date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY date;

\echo
\echo === inflação: janela 7d vs 21d anteriores ===
WITH recent AS (
  SELECT AVG(increase)::numeric(20,2) AS avg_inc
  FROM gold_log
  WHERE date >= CURRENT_DATE - INTERVAL '7 days'
),
prev AS (
  SELECT AVG(increase)::numeric(20,2) AS avg_inc
  FROM gold_log
  WHERE date >= CURRENT_DATE - INTERVAL '28 days'
    AND date <  CURRENT_DATE - INTERVAL '7 days'
)
SELECT
  recent.avg_inc                                 AS avg_inc_7d,
  prev.avg_inc                                   AS avg_inc_21d_anteriores,
  CASE WHEN prev.avg_inc > 0
       THEN ROUND(recent.avg_inc / prev.avg_inc, 2)
       ELSE NULL END                             AS razao,
  CASE WHEN prev.avg_inc > 0 AND recent.avg_inc / prev.avg_inc >= 2.0
       THEN 'ALERTA: inflação >= 2x'
       ELSE 'ok' END                             AS status
FROM recent, prev;
