-- Revenue rows, classified by crosswalk MEMBERSHIP rather than item-code
-- first letter (see 20-spending_long.sql for why prefixes cannot work).
-- Scope is Census General Revenue: every crosswalk revenue subtype EXCEPT
-- insurance_trust (Y01/Y02/Y04/Y11/Y12/Y51/Y52). Owner ruling 2026-07-30:
-- the default revenue concept stays general; surfacing insurance-trust
-- revenue through an explicit concept argument is uscogdata#12.
CREATE OR REPLACE VIEW revenue_long AS
SELECT *
FROM long
WHERE item_code IN (
    SELECT item_code FROM summary_categories
    WHERE category_type = 'revenue'
      AND revenue_subtype <> 'insurance_trust'
  )
  AND NOT is_aggregate;
