-- Harmonized-basis twin of 21-revenue_long.sql: same crosswalk-membership
-- classification (General Revenue = revenue minus insurance_trust), applied
-- to harmonized_code rather than the published item_code.
CREATE OR REPLACE VIEW revenue_long_harmonized AS
SELECT * REPLACE (harmonized_code AS item_code)
FROM long
WHERE NOT is_aggregate
  AND harmonized_code IS NOT NULL
  AND harmonized_code IN (
    SELECT item_code FROM summary_categories
    WHERE category_type = 'revenue'
      AND revenue_subtype <> 'insurance_trust'
  );
