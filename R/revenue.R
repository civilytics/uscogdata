# R/revenue.R

#' Summarized revenue by category
#'
#' Mirror of [cog_spending()] for revenue categories. One row per
#' `(year, canonical_govid, revenue_subtype, category)`. Amounts are returned
#' in **full U.S. dollars** (raw Census values are in $1,000s; this verb
#' multiplies by 1000 and records the conversion in `provenance`).
#'
#' @inheritParams cog_spending
#' @param category Character vector of category names (from
#'   `summary_categories.category`), or `NULL` for all categories broken out
#'   one row each. The reserved value `"All Categories"` instead returns a
#'   single summed row per `(year, canonical_govid, subtype)`, covering every
#'   category inside the requested concept's subtype scope. It cannot be
#'   combined with other category names, and it is not the same thing as
#'   `revenue_concept = "total"`: the concept chooses which subtypes are in
#'   scope, `"All Categories"` chooses whether rows inside that scope are
#'   broken out or summed. Because the result keeps one row per
#'   `revenue_subtype`, filtering the returned frame to
#'   `revenue_subtype == "own_source"` gives an own-source revenue total.
#' @param revenue_concept Which of Census's two published revenue concepts to
#'   return. Concepts are defined as sets of the crosswalk's `revenue_subtype`
#'   values -- never as item-code first letters, which cannot classify
#'   correctly (prefix `Y` spans revenue, expenditure and balance codes, and
#'   prefix `X` does the same):
#'
#'   * `"general"` (default) -- Census General Revenue: `own_source` +
#'     `federal` + `state` + `local_aid`. The manual defines this concept by
#'     subtraction (section 4.3: *"General revenue comprises all revenue
#'     except that classified as liquor store, utility, or insurance trust
#'     revenue"*), so utility (`A91`-`A94`), liquor store (`A90`) and
#'     insurance trust revenue are all excluded.
#'   * `"total"` -- Census Total Revenue: every revenue subtype, i.e.
#'     `general` plus utility, liquor store, and insurance trust revenue
#'     (`Y01`/`Y02`/`Y04`/`Y11`/`Y12`/`Y51`/`Y52` and the employee-retirement
#'     `X01`/`X02`/`X05`/`X08`).
#'
#'   The two are related by Census's own identity, `Total Revenue = General +
#'   Utility + Liquor Store + Insurance Trust`.
#'
#'   Note that the employee-retirement (`X`) codes stop at FY2016, when those
#'   systems moved out of the annual finance file into the separate Annual
#'   Survey of Public Pensions, so a `"total"` series steps down at the
#'   FY2016/FY2017 seam for reasons that are about collection scope rather
#'   than revenue (series breaks `SB197`-`SB202`).
#' @return Tibble with columns `year`, `canonical_govid`, `gov_name`,
#'   `revenue_subtype`, `category`, `amt_nominal`, optional `amt_real`,
#'   optional `amt_per_capita_nominal`, optional `amt_per_capita_real`,
#'   optional `pop_source`, `codes_included`, `aggregate_fallback`, `notes`,
#'   and `value_source` when `complete = TRUE`.
#' @export
cog_revenue <- function(govid, years, category = NULL,
                        per_capita = FALSE, adjust_to_year = NULL,
                        basis = c("harmonized", "raw"), recipe = NULL,
                        revenue_concept = c("general", "total"),
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
    revenue_concept = revenue_concept,
    complete       = complete
  )
}
