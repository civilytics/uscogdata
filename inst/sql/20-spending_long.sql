CREATE OR REPLACE VIEW spending_long AS
SELECT *
FROM long
WHERE LEFT(item_code, 1) IN ('E', 'F', 'G')
  AND NOT is_aggregate;
