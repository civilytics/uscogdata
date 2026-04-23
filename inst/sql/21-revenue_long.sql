CREATE OR REPLACE VIEW revenue_long AS
SELECT *
FROM long
WHERE LEFT(item_code, 1) IN ('T', 'A', 'U', 'B', 'C', 'D')
  AND NOT is_aggregate;
