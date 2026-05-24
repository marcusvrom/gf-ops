-- 05-auction-extremes.sql — preços de leilão muito acima da mediana do item.
-- Banco: gf_gs. Rode com:  psql -d gf_gs -f 05-auction-extremes.sql
--
-- O leilão é vetor clássico de duping (CLAUDE.md / server-files-notes.md).
-- Heurística: lance >= 100× a mediana de auction_price do MESMO item_id nas
-- últimas 90 entradas. Filtra item_ids com amostragem mínima (>= 5 leilões)
-- pra evitar falso positivo em itens raros.

\echo === lances >= 100x mediana do item ===
WITH med AS (
  SELECT item_id,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY auction_price) AS med_price,
         COUNT(*) AS n
  FROM auction
  GROUP BY item_id
  HAVING COUNT(*) >= 5
)
SELECT
  a.item_id,
  a.seller_id,
  a.auction_price,
  med.med_price,
  ROUND(a.auction_price::numeric / NULLIF(med.med_price, 0), 1) AS x_mediana,
  a.due_date
FROM auction a
JOIN med USING (item_id)
WHERE a.auction_price >= 100 * med.med_price
  AND med.med_price > 0
ORDER BY x_mediana DESC NULLS LAST
LIMIT 50;

\echo
\echo === vendedores mais ativos (top 20 últimos 7 dias por nº de leilões) ===
SELECT seller_id, COUNT(*) AS leiloes, SUM(auction_price) AS soma_pedida
FROM auction
WHERE due_date >= NOW() - INTERVAL '7 days'
GROUP BY seller_id
ORDER BY leiloes DESC
LIMIT 20;
