-- Harmonized-basis twin of 20-spending_long.sql: same crosswalk-membership
-- classification, applied to harmonized_code (the code the row is folded
-- onto) rather than the published item_code. Safe because the harmonized
-- space is leaf-only and every harmonized_code in the corpus is a
-- summary_categories member (verified at fixture regen; a code the
-- crosswalk cannot classify would be silently dropped here).
CREATE OR REPLACE VIEW spending_long_harmonized AS
SELECT * REPLACE (harmonized_code AS item_code)
FROM long
WHERE NOT is_aggregate
  AND harmonized_code IS NOT NULL
  AND harmonized_code IN (
    SELECT item_code FROM summary_categories
    WHERE category_type = 'expenditure'
      AND spend_subtype <> 'intergovernmental'
  );
