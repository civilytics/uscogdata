-- Direct-side expenditure rows, classified by crosswalk MEMBERSHIP
-- (summary_categories.category_type = 'expenditure'), never by item-code
-- first letter: prefix Y alone spans revenue (Y01/Y02), expenditure
-- (Y05/Y06) and balance codes, so no first-letter allowlist can route it
-- (uscogdata#11, finding F-018). Which subtypes a query actually returns is
-- decided per expenditure_concept in R (.verb_spendrev); this view carries
-- every non-intergovernmental expenditure subtype: operations, capital,
-- assistance, interest, insurance_benefits.
--
-- The intergovernmental subtype (M/L/Q codes) is deliberately carved out
-- into ig_long: its legacy-era rows are published ONLY as aggregate-flagged
-- rows, so it cannot live behind this view's NOT is_aggregate filter (see
-- 24-ig_long.sql).
CREATE OR REPLACE VIEW spending_long AS
SELECT *
FROM long
WHERE item_code IN (
    SELECT item_code FROM summary_categories
    WHERE category_type = 'expenditure'
      AND spend_subtype <> 'intergovernmental'
  )
  AND NOT is_aggregate;
