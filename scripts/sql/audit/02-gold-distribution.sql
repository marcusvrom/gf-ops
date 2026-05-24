-- 02-gold-distribution.sql — distribuição de gold pelas faixas range1..range10.
-- Banco: gf_gs. Rode com:  psql -d gf_gs -f 02-gold-distribution.sql
--
-- O servidor já agrega contagens de personagens em 10 faixas de gold por dia.
-- Concentração crescente em range9/range10 = ricos ficando mais ricos.
-- Útil cruzar com gold_outliers.sql (03) pra identificar QUEM.

\echo === distribuição mais recente (último dia em gold_log) ===
SELECT
  date,
  range1, range2, range3, range4, range5,
  range6, range7, range8, range9, range10
FROM gold_log
ORDER BY date DESC
LIMIT 1;

\echo
\echo === evolução do topo (range9+range10) últimos 14 dias ===
SELECT
  date,
  range9,
  range10,
  range9 + range10 AS topo_total
FROM gold_log
WHERE date >= CURRENT_DATE - INTERVAL '14 days'
ORDER BY date;
