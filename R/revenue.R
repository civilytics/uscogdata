# R/revenue.R

#' Summarized revenue by category
#'
#' Mirror of [cog_spending()] for revenue categories. One row per
#' `(year, canonical_govid, revenue_subtype, category)`. Amounts are returned
#' in **full U.S. dollars** (raw Census values are in $1,000s; this verb
#' multiplies by 1000 and records the conversion in `provenance`).
#'
#' @inheritParams cog_spending
#' @return Tibble with columns `year`, `canonical_govid`, `gov_name`,
#'   `revenue_subtype`, `category`, `amt_nominal`, optional `amt_real`,
#'   optional `amt_per_capita_nominal`, optional `amt_per_capita_real`,
#'   optional `pop_source`, `codes_included`, `aggregate_fallback`, `notes`,
#'   and `value_source` when `complete = TRUE`.
#' @export
cog_revenue <- function(govid, years, category = NULL,
                        per_capita = FALSE, adjust_to_year = NULL,
                        basis = c("harmonized", "raw"), recipe = NULL,
                        complete = FALSE) {
  # flow_prefixes no longer classifies rows (crosswalk revenue_subtype
  # membership does -- General Revenue, i.e. everything except
  # insurance_trust) -- it only scopes the recipe-suggestion machinery to
  # this verb's recipe families (see R/suggestions.R).
  .verb_spendrev(
    verb           = "cog_revenue",
    view_base      = "revenue_annotated",
    subtype_col    = "revenue_subtype",
    flow_prefixes  = c("T", "A", "U", "B", "C", "D"),
    call           = match.call(),
    govid          = govid,
    years          = years,
    category       = category,
    per_capita     = per_capita,
    adjust_to_year = adjust_to_year,
    basis          = basis,
    recipe         = recipe,
    complete       = complete
  )
}
