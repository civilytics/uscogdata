# R/categories.R

#' List available spending / revenue categories
#'
#' Returns the category taxonomy exposed by the corpus's
#' `summary_categories` view, grouped to one row per
#' `(category, subtype)` pair. Use this to discover valid `category`
#' values for [cog_spending()] / [cog_revenue()] / [cog_balances()] /
#' [cog_geographic_rollup()] and to audit which Census item codes feed
#' each category.
#'
#' `subtype` COALESCEs the crosswalk's three subtype columns, so it carries
#' `spend_subtype` on expenditure rows, `revenue_subtype` on revenue rows and
#' `balance_subtype` on balance rows. Note that [cog_balances()] itself takes
#' no `subtype` argument — for holdings, `category` is a strict coarsening of
#' `balance_subtype` — but the value is surfaced here because it is the
#' discovery surface downstream consumers build their vocabulary from.
#'
#' @param type Either `NULL` (default, every row: expenditure, revenue and
#'   balance), `"spending"`, `"revenue"`, or `"balance"`.
#' @param pattern Optional regex matched case-insensitively against the
#'   `category` column (e.g. `"Police"` or `"Tax"`).
#' @return Tibble with columns `category`, `category_type`, `subtype`,
#'   `n_codes`, `item_codes` (comma-separated, alphabetical). Sorted by
#'   `category_type`, `category`, `subtype`. Includes one row per flow for the
#'   reserved pseudo-category `"All Categories"`, which carries `NA` for
#'   `subtype`, `n_codes` and `item_codes` because it is a query mode rather
#'   than a crosswalk entry — see [cog_spending()]'s `category` argument.
#' @export
cog_categories <- function(type = NULL, pattern = NULL) {
  if (!is.null(type)) {
    if (!is.character(type) || length(type) != 1L ||
        !type %in% c("spending", "revenue", "balance")) {
      cli::cli_abort('`type` must be NULL, "spending", "revenue", or "balance".')
    }
  }
  if (!is.null(pattern) &&
      (!is.character(pattern) || length(pattern) != 1L)) {
    cli::cli_abort("`pattern` must be a length-1 character string or NULL.")
  }

  con <- .ensure_session()

  preds <- character(0)
  if (!is.null(type)) {
    # Translate user-facing "spending" to the corpus's native "expenditure"
    # value so callers don't have to learn Census vocabulary. "revenue" is
    # the same in both.
    db_type <- if (type == "spending") "expenditure" else type
    preds <- c(preds, sprintf("category_type = %s", .sql_lit_chr(db_type)))
  }
  if (!is.null(pattern)) {
    preds <- c(preds,
               sprintf("regexp_matches(category, %s, 'i')",
                       .sql_lit_chr(pattern)))
  }
  where <- if (length(preds) == 0L) "" else paste("WHERE", paste(preds, collapse = " AND "))

  sql <- paste(
    "SELECT category, category_type,
            COALESCE(spend_subtype, revenue_subtype, balance_subtype) AS subtype,
            COUNT(DISTINCT item_code) AS n_codes,
            string_agg(DISTINCT item_code, ',' ORDER BY item_code) AS item_codes
     FROM summary_categories",
    where,
    "GROUP BY category, category_type, subtype
     ORDER BY category_type, category, subtype"
  )
  out <- tibble::as_tibble(DBI::dbGetQuery(con, sql))

  # The reserved pseudo-category is a query mode, not a crosswalk row, so it
  # has no item codes to report -- hence NA rather than 0 for n_codes. It is
  # emitted for the two FLOW vocabularies only: cog_balances() returns a stock
  # and has no concept argument to sum within.
  pseudo <- tibble::tibble(
    category      = .ALL_CATEGORIES,
    category_type = c("expenditure", "revenue"),
    subtype       = NA_character_,
    n_codes       = NA_integer_,
    item_codes    = NA_character_
  )
  if (!is.null(type)) {
    db_type <- if (type == "spending") "expenditure" else type
    pseudo <- pseudo[pseudo$category_type == db_type, , drop = FALSE]
  }
  if (!is.null(pattern) && nrow(pseudo) > 0L) {
    keep <- grepl(pattern, pseudo$category, ignore.case = TRUE)
    pseudo <- pseudo[keep, , drop = FALSE]
  }
  if (nrow(pseudo) == 0L) return(out)
  out <- rbind(out, pseudo)
  out[order(out$category_type, out$category, out$subtype), , drop = FALSE]
}
