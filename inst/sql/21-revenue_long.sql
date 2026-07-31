-- Revenue rows, classified by crosswalk MEMBERSHIP rather than item-code
-- first letter (see 20-spending_long.sql for why prefixes cannot work).
--
-- Carries EVERY revenue subtype. Which of Census's two published concepts a
-- query actually returns is decided per revenue_concept in R
-- (.verb_spendrev), exactly as expenditure_concept narrows spending_long:
--   general = own_source + federal + state + local_aid   (the default)
--   total   = general + utility + liquor_store + insurance_trust
-- Census defines the first by subtracting the other three from the second
-- (manual section 4.3), so both concepts need all four families present here.
CREATE OR REPLACE VIEW revenue_long AS
SELECT *
FROM long
WHERE item_code IN (
    SELECT item_code FROM summary_categories
    WHERE category_type = 'revenue'
  )
  AND NOT is_aggregate;
