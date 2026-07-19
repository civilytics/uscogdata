CREATE OR REPLACE VIEW spending_long_harmonized AS
SELECT * REPLACE (harmonized_code AS item_code)
FROM long
WHERE NOT is_aggregate
  AND harmonized_code IS NOT NULL
  AND LEFT(harmonized_code, 1) IN ('E', 'F', 'G', 'K');
