-- Harmonized-basis IG rows. Uses COALESCE(harmonized_code, item_code) rather
-- than harmonized_code alone: aggregate rows carry NO harmonized_code by
-- construction (harmonized space is leaf-only), so a plain
-- `harmonized_code IS NOT NULL` filter would drop every legacy IG aggregate --
-- in the bundled fixture corpus (year 2011; 2012+ all carry a harmonized_code)
-- that is $379,016,063k across 25,688 M rows and $2,277,458k across 19,266 L
-- rows (`SELECT year, LEFT(item_code,1), SUM(amt), COUNT(*) FROM ig_long
-- WHERE harmonized_code IS NULL GROUP BY 1, 2`). COALESCE keeps the one real
-- IG collapse rule (M38 -> M36, SB012, year-disjoint 1967-2011 vs 2012+)
-- while never dropping a row.
--
-- Membership is checked on the published item_code (mirroring 24-ig_long.sql)
-- rather than the COALESCEd code: every IG harmonization target (M36) is
-- itself an IG crosswalk member, so the two are equivalent, and item_code is
-- the column that exists on every row.
CREATE OR REPLACE VIEW ig_long_harmonized AS
SELECT * REPLACE (COALESCE(harmonized_code, item_code) AS item_code)
FROM long
WHERE item_code IN (
    SELECT item_code FROM summary_categories
    WHERE spend_subtype = 'intergovernmental'
  );
