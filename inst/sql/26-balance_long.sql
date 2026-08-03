-- Cash and security holdings, classified by crosswalk MEMBERSHIP on
-- category_type (see 21-revenue_long.sql for why first-letter prefixes cannot
-- do this job -- the X and Y families each span revenue, expenditure AND
-- balance).
--
-- These rows are STOCKS: a balance at a point in time, not a flow over a
-- fiscal year. Summing a stock with a flow is meaningless, which is why they
-- live behind a third view rather than as a subtype of either money view, and
-- why neither spending_long nor revenue_long can reach them.
--
-- `NOT is_aggregate` mirrors spending_long / revenue_long. The wide-era
-- aggregate-only holdings codes (X40/X41) are deliberately outside this view;
-- they are reachable only through the recipe path, which bypasses this filter
-- by design (cog_pipeline/docs/phase_r_harmonization_review.md § 0.2).
CREATE OR REPLACE VIEW balance_long AS
SELECT *
FROM long
WHERE item_code IN (
    SELECT item_code FROM summary_categories
    WHERE category_type = 'balance'
  )
  AND NOT is_aggregate;
