-- Harmonized-basis IG rows. Uses COALESCE(harmonized_code, item_code) rather
-- than harmonized_code alone: aggregate rows carry NO harmonized_code by
-- construction (harmonized space is leaf-only), so a plain
-- `harmonized_code IS NOT NULL` filter would drop every legacy IG aggregate --
-- 6.4e9 of M and 3.1e8 of L in corpus units. COALESCE keeps the one real IG
-- collapse rule (M38 -> M36, SB012, year-disjoint 1967-2011 vs 2012+) while
-- never dropping a row.
CREATE OR REPLACE VIEW ig_long_harmonized AS
SELECT * REPLACE (COALESCE(harmonized_code, item_code) AS item_code)
FROM long
WHERE LEFT(item_code, 1) IN ('M', 'L')
  AND item_code NOT LIKE '%--';
