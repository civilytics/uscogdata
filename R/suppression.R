# R/suppression.R
# Split out of R/suggestions.R (2026-08-05) to keep files under the project's
# 400-line limit. Owns the second qualifying path for coverage signposting
# (uscogdata#9): measuring, per government, the component dollars the
# calling verb's own long view structurally excludes (aggregate-published,
# or absent from summary_categories). See R/suggestions.R for the
# orchestrator (`.build_suggestions()`) that calls this and the full
# uscogdata#9 background.

#' Measure, per (recipe, year), the component dollars this government holds
#' that the calling verb's own long view structurally excludes.
#'
#' This is the second qualifying path for a suggestion (uscogdata#9). The
#' first -- row absence -- only fires when a category returns NOTHING in a
#' requested year, which is how Corrections behaves in the wide era. Public
#' Welfare is the failure mode it misses: E74/E75/E77/E79 still return rows,
#' so there is no absence to detect, while E67/E68 (aggregate-flagged 1967-
#' 2011, and absent from `summary_categories` entirely) are dropped. The
#' caller gets a plausible number a third too low, silently.
#'
#' "Structurally excluded" is decided by anti-joining the verb's REAL long
#' view rather than restating its WHERE clause, so this stays correct if
#' `spending_long_harmonized` / `revenue_long_harmonized` ever change. That
#' anti-join is keyed on `item_code`, which is sound only because
#' harmonization never renames a recipe component -- asserted by the "no
#' recipe component is ever renamed by harmonization" test in
#' tests/testthat/test-recipes.R.
#'
#' Note what this deliberately does NOT count as suppressed: a component
#' excluded from the RESULT for scoping reasons -- because it belongs to a
#' different `category`, or because `expenditure_concept` narrowed the
#' subtypes -- is still present in the view, so it never fires. Suggesting a
#' recipe is a coverage fix, not a category redefinition.
#'
#' `flow_prefixes` (uscogdata#9 review, finding I1) restricts the measured
#' components to the CALLING VERB's own flow family (`c("E","F","G")` for
#' spending, `c("T","A","U","B","C","D")` for revenue). Without this, a
#' candidate recipe belonging to the OTHER flow family is always absent from
#' this verb's view (by construction -- `cog_revenue()`'s view never carries
#' an E-coded row) and so was always reported as "suppressed", fabricating a
#' dollar claim across flow families (`cog_revenue(category = "Corrections")`
#' claimed $3.63B excluded that `cog_spending()` reports and fully accounts
#' for). Filtering on `LEFT(r.component_code, 1)` also drops M/L-prefixed
#' components from measurement under `cog_spending()` (`flow_prefixes` never
#' includes "M"/"L") -- harmless today, because a recipe's own M/L components
#' (e.g. `corrections_ig_local_combined`'s M04/M05) are present in the view
#' in every year they exist and so never fired as suppressed anyway, but
#' worth recording since this filter is now the thing relied on to prevent
#' it.
#'
#' @param con Active DuckDB connection.
#' @param candidates Character vector of recipe ids to measure.
#' @param govid Character vector of canonical_govid values.
#' @param years Integer vector of requested years.
#' @param long_view Name of the verb's long view, from `.select_long_view()`.
#' @param flow_prefixes The calling verb's own flow-type prefixes (see
#'   `.build_suggestions()`). Only recipe components whose first character is
#'   in this set are measured.
#' @return Tibble of `recipe_id`, `year`, `suppressed_amount` (full US
#'   dollars), `suppressed_codes` (comma-joined, sorted). Zero rows when
#'   nothing is suppressed.
#' @noRd
.suppressed_components <- function(con, candidates, govid, years, long_view,
                                    flow_prefixes) {
  empty <- tibble::tibble(
    recipe_id = character(0), year = numeric(0),
    suppressed_amount = numeric(0), suppressed_codes = character(0)
  )
  if (length(candidates) == 0L) return(empty)

  # long_view is interpolated as a SQL IDENTIFIER, not a literal, so it can
  # never be quoted safely. It is always internally derived from a fixed
  # view_base, so an off-allowlist value is a programming error, not input.
  if (!long_view %in% c("spending_long", "spending_long_harmonized",
                        "revenue_long", "revenue_long_harmonized")) {
    cli::cli_abort(
      "Internal error: unexpected `long_view` {.val {long_view}}.",
      class = "uscogdata_internal_error"
    )
  }

  sql <- sprintf(
    "SELECT r.recipe_id,
            l.year,
            SUM(l.amt) * 1000.0 AS suppressed_amount,
            string_agg(DISTINCT l.item_code, ',' ORDER BY l.item_code)
              AS suppressed_codes
     FROM long l
     JOIN harmonization_recipes r
       ON l.item_code = r.component_code
      AND l.year BETWEEN r.year_min AND r.year_max
      AND (r.gov_type_scope = 'all'
           OR (r.gov_type_scope = 'state' AND l.type = 0)
           OR (r.gov_type_scope = 'local' AND l.type BETWEEN 1 AND 3))
     WHERE r.recipe_id IN (%1$s)
       AND l.canonical_govid IN (%2$s)
       AND l.year IN (%3$s)
       AND l.amt <> 0
       AND LEFT(r.component_code, 1) IN (%5$s)
       AND NOT EXISTS (
         SELECT 1 FROM %4$s v
         WHERE v.canonical_govid = l.canonical_govid
           AND v.year = l.year
           AND v.item_code = l.item_code
           AND v.year IN (%3$s)              -- restated: enables partition pruning (I3a)
           AND v.canonical_govid IN (%2$s)   -- restated: pushes the govid filter (I3a)
       )
     GROUP BY 1, 2
     ORDER BY 1, 2",
    .sql_lit_chr(candidates), .sql_lit_chr(govid),
    paste(as.integer(years), collapse = ","), long_view,
    .sql_lit_chr(flow_prefixes)
  )
  tibble::as_tibble(DBI::dbGetQuery(con, sql))
}
