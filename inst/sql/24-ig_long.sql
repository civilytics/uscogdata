-- Intergovernmental expenditure rows: crosswalk spend_subtype =
-- 'intergovernmental' (M = to local govts, L = to state govts, Q11/Q12/Q18
-- = state payments to school systems -- uscogdata#11, finding F-017).
--
-- Deliberately does NOT filter `NOT is_aggregate`, unlike spending_long. In the
-- wide era (<= FY2011) the IG families M05/M12/M47/M89/L47/L89 are published
-- ONLY as aggregate-flagged rows -- filtering them would hide ~70% of legacy IG
-- dollars and make Total silently collapse to Direct. This is safe because the
-- aggregate codes and their modern leaf components are strictly year-disjoint
-- (M47 ends 2011 / M94 starts 2012; M89 is aggregate only <= 2011 and a leaf
-- from 2012 alongside M91-93), so no row is ever counted twice. Same argument
-- the pipeline's recipe joins use.
--
-- `L--` stays excluded: it is the IG-to-state FAMILY TOTAL and genuinely
-- rolls up the L-NN codes, so including it would double-count. The crosswalk
-- deliberately carries no `--` family-total codes, so membership excludes it
-- (guarded by "the IG leg never includes the L-- family total" in
-- tests/testthat/test-expenditure-concept.R).
CREATE OR REPLACE VIEW ig_long AS
SELECT *
FROM long
WHERE item_code IN (
    SELECT item_code FROM summary_categories
    WHERE spend_subtype = 'intergovernmental'
  );
