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
#'   `canonical_govid` column (e.g. from [cog_gov_search()]).
#' @param years Integer vector of fiscal years.
#' @param category Optional character vector of categories to keep. One of
#'   `"Fund Balances"`, `"Insurance Trust Balances"`,
#'   `"Retirement System Holdings"`. There is deliberately no `subtype`
#'   argument: for holdings, `category` is a strict coarsening of
#'   `balance_subtype` (unlike the money verbs, where the two axes cross), so
#'   every combination would be either redundant or empty.
#'   `category = "Fund Balances"` is exactly the `general` family
#'   (`W01`/`W31`/`W61`). `balance_subtype` is returned, so a finer split is
#'   one `dplyr::filter()` away.
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
#'
#' @return A `tbl_df` with a `provenance` attribute. Amounts are full US
#'   dollars.
#' @export
cog_balances <- function(govid, years, category = NULL,
                         per_capita = FALSE, adjust_to_year = NULL,
                         basis = c("harmonized", "raw"), recipe = NULL) {
  call <- match.call()
  basis <- match.arg(basis, c("harmonized", "raw"))
  .validate_balance_inputs(per_capita, adjust_to_year)
  govid <- .coerce_govid_input(govid)
  years <- as.integer(years)
  if (!is.null(adjust_to_year)) adjust_to_year <- as.integer(adjust_to_year)

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

  if (!is.null(recipe)) {
    .require_schema_v5(con, manifest, "recipe =")
    .validate_recipe_id(con, recipe)
    comps <- .recipe_components(con, recipe)
    recipe_label <- comps$label[[1]]
    result <- .run_recipe(con, recipe, govid, years)
    sql <- attr(result, "sql_query")
    result <- .shape_recipe_result(result, "balance_subtype", recipe_label)
    recipe_block <- list(
      recipe_id = recipe, label = recipe_label,
      components = .df_to_row_list(comps)
    )
    category_for_prov <- recipe_label
  } else {
    sql <- .build_verb_sql("balance_annotated", "balance_subtype",
                           govid, years, category,
                           ig_view = NULL, subtype_scope = NULL)
    result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  }

  # Order matters (matches .verb_spendrev()): per-capita first, so
  # .attach_real_dollars() deflates the nominal per-capita column into
  # amt_per_capita_real rather than needing amt_per_capita_nominal recomputed.
  if (isTRUE(per_capita)) result <- .attach_per_capita(result, con, govid)
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

  attr(result, "provenance") <- prov
  result
}

#' Cheap type validation for the two arguments cog_balances() shares with the
#' money verbs. Mirrors the per_capita/adjust_to_year checks in
#' .validate_verb_inputs() (R/spending.R) -- category/recipe validation is
#' deliberately out of scope here (uscogdata#25 Task 3 review note).
#' @noRd
.validate_balance_inputs <- function(per_capita, adjust_to_year) {
  if (!is.logical(per_capita) || length(per_capita) != 1L) {
    cli::cli_abort("`per_capita` must be a length-1 logical.")
  }
  if (!is.null(adjust_to_year)) {
    if (!(is.integer(adjust_to_year) || is.numeric(adjust_to_year)) ||
        length(adjust_to_year) != 1L) {
      cli::cli_abort("`adjust_to_year` must be NULL or a length-1 integer.")
    }
  }
  invisible(TRUE)
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
