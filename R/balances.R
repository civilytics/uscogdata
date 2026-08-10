# R/balances.R
#
# Cash and security holdings. A third verb rather than an argument on a money
# verb because holdings are a STOCK -- a balance at a point in time -- while
# cog_spending()/cog_revenue() return FLOWS over a fiscal year. The money
# verbs' whole argument vocabulary (expenditure_concept, revenue_concept,
# complete=) describes flows and is meaningless here, so this deliberately
# does NOT route through .verb_spendrev().

#' Cash and security holdings for one or more governments
#'
#' Returns Census cash-and-security holdings (`category_type = "balance"`):
#' fund balances, retirement system holdings and insurance trust balances.
#'
#' @section Holdings are not GAAP fund balance:
#' Census holdings are **gross** -- no liabilities are netted -- so a reserve
#' ratio built from them overstates what is actually available. They are not
#' comparable to a GAAP fund balance from an ACFR.
#'
#' @param govid Canonical govid(s): a character vector, or a data frame with a
#'   `canonical_govid` column (e.g. from [cog_gov_search()]). `NULL` to name
#'   the cohort by `state`/`type` instead.
#' @inheritParams cog_spending
#' @param years Integer vector of fiscal years.
#' @param category Optional character vector of categories to keep. One of
#'   `"Fund Balances"`, `"Insurance Trust Balances"`,
#'   `"Retirement System Holdings"`. There is deliberately no `subtype`
#'   argument: for holdings, `category` is a strict coarsening of
#'   `balance_subtype` (unlike the money verbs, where the two axes cross), so
#'   every combination would be either redundant or empty.
#'   `category = "Fund Balances"` is exactly the `general` family
#'   (`W01`/`W31`/`W61`). `balance_subtype` is returned, so a finer split is
#'   one `dplyr::filter()` away. The reserved pseudo-category
#'   `"All Categories"` (see [cog_spending()]) is **not** supported here and
#'   errors with class `uscogdata_all_categories_unsupported`: it sums a
#'   concept's subtype scope, and holdings are a stock with no concept
#'   vocabulary to sum across. Omit `category` to get every category broken
#'   out instead.
#' @param per_capita Divide holdings by population. Note this is a **stock per
#'   resident** (reserves per person), which is *not* comparable to
#'   [cog_spending()]'s per-capita figures -- those are a flow per person.
#' @param adjust_to_year Deflate to this year's dollars (CPI-U).
#' @param basis Accepted for uniformity with the money verbs, but currently a
#'   **no-op**: `harmonization_map` carries no balance-code rows, so harmonized
#'   and raw space are identical for holdings. Reported in
#'   `provenance$basis_note`.
#' @param recipe Optional harmonization recipe id (see [cog_recipes()]).
#'   `"cash_securities_z77_wide"` and `"cash_securities_z78_wide"` bridge the
#'   wide era to the modern one.
#' @param limit Maximum number of result rows to return, pushed into the SQL
#'   rather than applied after materializing every row. `NULL` (default)
#'   returns everything. Cannot be combined with `recipe` -- see `offset` and
#'   `total_rows`.
#' @param offset Rows to skip before `limit` starts counting (0-based).
#'   Ignored if `limit` is `NULL`; defaults to `0L` when `limit` is set.
#'
#' @return Tibble with columns `year`, `canonical_govid`, `gov_name`,
#'   `balance_subtype`, `category`, `amt_nominal`, `codes_included`,
#'   `aggregate_fallback`, plus optional `amt_per_capita_nominal` and
#'   `pop_source` (when `per_capita = TRUE`), optional `amt_real` (when
#'   `adjust_to_year` is set), and optional `amt_per_capita_real` (only when
#'   **both** `per_capita = TRUE` and `adjust_to_year` are set -- there is no
#'   nominal per-capita column to deflate otherwise). Amounts are full US
#'   dollars.
#'
#'   Carries a `provenance` attribute matching
#'   `inst/schemas/provenance-v1.json`, whose `balance_caveats` block reports
#'   `not_gaap`, `not_gaap_note`, `coverage_window` (measured year extents for
#'   every balance subtype in the mounted corpus, not only the observed ones)
#'   and `truncated` (the observed subtypes whose coverage falls short of the
#'   requested years). `expenditure_concept`/`revenue_concept` are `NA` --
#'   holdings are a stock, not a flow, so neither concept vocabulary applies.
#'
#'   When `limit` is set, also carries a `total_rows` attribute: the full
#'   unpaginated row count, computed by the same query (`COUNT(*) OVER()`)
#'   rather than a second scan.
#' @export
cog_balances <- function(govid = NULL, years, category = NULL,
                         per_capita = FALSE, adjust_to_year = NULL,
                         basis = c("harmonized", "raw"), recipe = NULL,
                         state = NULL, type = NULL,
                         limit = NULL, offset = NULL) {
  call <- match.call()
  basis <- match.arg(basis, c("harmonized", "raw"))
  # Coerce FIRST, validate second: .validate_verb_inputs() asserts
  # is.character(govid), and a data-frame govid (cog_gov_search() output) has
  # not been unwrapped yet at this point.
  govid <- if (is.null(govid)) NULL else .coerce_govid_input(govid)
  # The money verbs' validator, reused rather than re-implemented (R/spending.R).
  # It covers the exact superset cog_balances() needs -- including the
  # recipe/category mutual-exclusivity guard -- so a second local copy would
  # only be a place for the two to drift apart. This is the same kind of
  # helper reuse as .build_verb_sql()/.attach_per_capita() below; it does NOT
  # route the verb through .verb_spendrev(), which stays deliberately unused
  # here because its flow vocabulary is meaningless for a stock.
  #
  # allow_all_categories is left at its FALSE default (contrast
  # .verb_spendrev(), which passes TRUE): the all-categories mode's "sum"
  # only means something in terms of a concept's subtype scope, and holdings
  # have no concept vocabulary. The reuse above is exactly why this can be a
  # one-line default rather than a second bespoke check -- see the
  # validator's own doc comment for the incident that made that matter.
  .validate_verb_inputs(govid, years, category, per_capita, adjust_to_year,
                        recipe)

  # Same semantics as the money verbs (R/pagination.R). Only the `recipe`
  # conflict applies here: cog_balances() has no `complete` argument, and a
  # recipe's result comes from .run_recipe()'s own query, which pagination is
  # not wired into.
  paging <- .validate_pagination(limit, offset)
  limit  <- paging$limit
  offset <- paging$offset
  if (!is.null(limit) && !is.null(recipe)) {
    cli::cli_abort(c(
      "`limit`/`offset` cannot be combined with `recipe`.",
      "i" = "A recipe's result comes from a separate query (`.run_recipe()`) that pagination is not wired into yet.",
      "*" = "Drop `limit`/`offset`, or drop `recipe`."
    ), class = "uscogdata_recipe_pagination_conflict")
  }

  years <- as.integer(years)
  if (!is.null(adjust_to_year)) adjust_to_year <- as.integer(adjust_to_year)

  cohort <- .make_cohort(govid, state, type)

  con <- .ensure_session()
  .require_balance_support(con)
  scope <- .check_govids_in_scope(govid)

  basis_note <- paste0(
    "`basis` has no effect on holdings: harmonization_map carries no ",
    "balance-code rows, so harmonized and raw space are identical here."
  )

  manifest <- .uscogdata_env$manifest
  recipe_block <- NULL
  category_for_prov <- category
  total_rows <- NULL  # set below only when limit is non-NULL (non-recipe path)

  if (!is.null(recipe)) {
    .require_schema_v5(con, manifest, "recipe =")
    .validate_recipe_id(con, recipe)
    comps <- .recipe_components(con, recipe)
    recipe_label <- comps$label[[1]]
    result <- .run_recipe(con, recipe, cohort, years)
    sql <- attr(result, "sql_query")
    result <- .shape_recipe_result(result, "balance_subtype", recipe_label)
    recipe_block <- list(
      recipe_id = recipe, label = recipe_label,
      components = .df_to_row_list(comps)
    )
    category_for_prov <- recipe_label
  } else {
    sql <- .build_verb_sql("balance_annotated", "balance_subtype",
                           cohort, years, category,
                           ig_view = NULL, subtype_scope = NULL,
                           limit = limit, offset = offset)
    result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
    if (!is.null(limit)) {
      paged <- .take_pagination_total(result, con, function() {
        .build_verb_sql("balance_annotated", "balance_subtype",
                        cohort, years, category,
                        ig_view = NULL, subtype_scope = NULL)
      })
      result     <- paged$result
      total_rows <- paged$total_rows
    }
  }

  # Order matters (matches .verb_spendrev()): per-capita first, so
  # .attach_real_dollars() deflates the nominal per-capita column into
  # amt_per_capita_real rather than needing amt_per_capita_nominal recomputed.
  if (isTRUE(per_capita)) result <- .attach_per_capita(result, con)
  if (!is.null(adjust_to_year)) {
    result <- .attach_real_dollars(result, adjust_to_year, per_capita)
  }

  prov <- .build_provenance(
    verb = "cog_balances", call = call, govid = govid, years = years,
    category = category_for_prov, per_capita = per_capita,
    adjust_to_year = adjust_to_year, result = result, sql = sql,
    subtype_col = "balance_subtype",
    basis = basis, basis_note = basis_note,
    # Neither concept vocabulary applies to a stock.
    expenditure_concept = NA_character_,
    revenue_concept = NA_character_,
    recipe = recipe_block
  )
  prov$scope$govids_found   <- scope$found
  prov$scope$govids_missing <- scope$missing
  prov$scope$cohort <- .cohort_provenance(con, cohort)

  prov$balance_caveats <- .balance_caveats(
    con, prov$codes_summed$observed, years
  )
  .emit_balance_caveats(prov$balance_caveats)

  attr(result, "provenance") <- prov
  if (!is.null(limit)) attr(result, "total_rows") <- total_rows
  result
}

#' Abort unless the mounted corpus classifies balance codes.
#'
#' `balance_subtype` arrived with cog_pipeline #76/#77 without a
#' schema_version bump, so the check is on the column, not the version.
#' @noRd
.require_balance_support <- function(con) {
  if (.corpus_has_balance_subtype(con)) return(invisible(TRUE))
  cli::cli_abort(
    c("This corpus does not classify cash and security holdings.",
      i = "`summary_categories` has no {.field balance_subtype} column.",
      i = "Republish from cog_pipeline at #76/#77 or later."),
    class = "uscogdata_no_balance_support"
  )
}
