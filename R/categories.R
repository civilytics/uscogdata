# R/categories.R

#' List available spending / revenue categories
#'
#' Returns the category taxonomy exposed by the corpus's
#' `summary_categories` view, grouped to one row per
#' `(category, subtype)` pair. Use this to discover valid `category`
#' values for [cog_spending()] / [cog_revenue()] /
#' [cog_geographic_rollup()] and to audit which Census item codes feed
#' each category.
#'
#' @param type Either `NULL` (default, return both spending and revenue
#'   rows), `"spending"`, or `"revenue"`.
#' @param pattern Optional regex matched case-insensitively against the
#'   `category` column (e.g. `"Police"` or `"Tax"`).
#' @return Tibble with columns `category`, `category_type`, `subtype`,
#'   `n_codes`, `item_codes` (comma-separated, alphabetical). Sorted by
#'   `category_type`, `category`, `subtype`.
#' @export
cog_categories <- function(type = NULL, pattern = NULL) {
  if (!is.null(type)) {
    if (!is.character(type) || length(type) != 1L ||
        !type %in% c("spending", "revenue")) {
      cli::cli_abort('`type` must be NULL, "spending", or "revenue".')
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
            COALESCE(spend_subtype, revenue_subtype) AS subtype,
            COUNT(DISTINCT item_code) AS n_codes,
            string_agg(DISTINCT item_code, ',' ORDER BY item_code) AS item_codes
     FROM summary_categories",
    where,
    "GROUP BY category, category_type, subtype
     ORDER BY category_type, category, subtype"
  )
  tibble::as_tibble(DBI::dbGetQuery(con, sql))
}
