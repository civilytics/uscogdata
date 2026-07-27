-- Intergovernmental expenditure rows (M = to local govts, L = to state govts).
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
-- `L--` IS excluded: it is the IG-to-state FAMILY TOTAL and genuinely rolls up
-- the L-NN codes, so including it would double-count.
CREATE OR REPLACE VIEW ig_long AS
SELECT *
FROM long
WHERE LEFT(item_code, 1) IN ('M', 'L')
  AND item_code NOT LIKE '%--';
