-- 03-gold-outliers.sql — top players por gold/crystal + outlier vs mediana.
-- Banco: gf_gs. Rode com:  psql -d gf_gs -f 03-gold-outliers.sql
--
-- "Outlier" aqui é uma heurística: gold >= 50× a mediana entre chars com level>=10
-- (ignora chars recém-criados que ainda têm gold inicial inflando a base).
-- Não é prova de dupe, é indício pra investigar.

\echo === top 20 por gold ===
SELECT id, given_name, account_id, level, gold, crystal
FROM player_characters
ORDER BY gold DESC NULLS LAST
LIMIT 20;

\echo
\echo === top 20 por crystal ===
SELECT id, given_name, account_id, level, gold, crystal
FROM player_characters
ORDER BY crystal DESC NULLS LAST
LIMIT 20;

\echo
\echo === outliers: gold >= 50x mediana (level >= 10) ===
WITH base AS (
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY gold) AS med
  FROM player_characters
  WHERE level >= 10 AND gold > 0
)
SELECT
  pc.id,
  pc.given_name,
  pc.account_id,
  pc.level,
  pc.gold,
  ROUND(pc.gold / NULLIF(base.med, 0), 1) AS x_mediana
FROM player_characters pc, base
WHERE pc.level >= 10
  AND base.med > 0
  AND pc.gold >= 50 * base.med
ORDER BY pc.gold DESC
LIMIT 50;
