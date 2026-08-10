# R/pagination.R
#
# Shared limit/offset machinery. #39 established the semantics inside
# .verb_spendrev(); #57 extends them to cog_gov_search() and cog_balances(),
# which is what made a single definition worth having: three inline copies of
# "coerce, refuse, unwrap the count" would be three places for the meaning of
# `total_rows` to drift.
#
# The SQL side stays in .build_verb_sql() (R/spending.R) -- it already wraps
# the aggregate in an outer SELECT so COUNT(*) OVER() sees the post-GROUP-BY
# row count rather than the pre-aggregation one, and that is the subtle part
# worth not duplicating either.

#' Coerce and check a limit/offset pair.
#'
#' Returns the coerced pair, or NULL for `limit` when no page was requested.
#' `offset` defaults to 0 whenever `limit` is set, so a caller can supply just
#' `limit` and get the first page.
#'
#' Conflicts with other arguments are deliberately NOT checked here: they
#' differ per verb (`complete`/`recipe` for the money verbs, basket mode for
#' `cog_gov_search()`, `recipe` alone for `cog_balances()`), and a shared
#' function taking a list of conflict flags would be harder to read than the
#' three explicit refusals at the call sites.
#' @noRd
.validate_pagination <- function(limit, offset) {
  if (is.null(limit)) {
    return(list(limit = NULL, offset = NULL))
  }
  limit <- as.integer(limit)
  if (length(limit) != 1L || is.na(limit) || limit < 0L) {
    cli::cli_abort("`limit` must be a single non-negative integer.",
                   class = "uscogdata_invalid_pagination")
  }
  offset <- if (is.null(offset)) 0L else as.integer(offset)
  if (length(offset) != 1L || is.na(offset) || offset < 0L) {
    cli::cli_abort("`offset` must be a single non-negative integer.",
                   class = "uscogdata_invalid_pagination")
  }
  list(limit = limit, offset = offset)
}

#' Wrap a query so one page comes back carrying the unpaginated total.
#'
#' `COUNT(*) OVER()` rides along as an ordinary column, so the caller gets the
#' true total from the SAME scan instead of a second round trip. The outer
#' `SELECT *` matters: appending LIMIT/OFFSET directly to a grouped query would
#' have the window function count pre-aggregation rows.
#' @noRd
.paginate_sql <- function(base_sql, limit, offset) {
  if (is.null(limit)) return(base_sql)
  sprintf(
    "SELECT *, COUNT(*) OVER() AS pagination_total_rows
     FROM (%s) AS _paged
     LIMIT %d OFFSET %d",
    base_sql, limit, offset
  )
}

#' Strip the count column back out and report the unpaginated total.
#'
#' Returns `list(result = , total_rows = )`.
#'
#' An empty page -- an offset past the end -- carries no row to read the window
#' function off, so that one case falls back to a second, unpaginated
#' `COUNT(*)` rather than reporting a wrong zero. `unpaged_sql` is passed as a
#' function so the fallback query is only BUILT when it is actually needed;
#' every caller's unpaginated SQL is otherwise constructed on every paged call
#' and thrown away.
#' @noRd
.take_pagination_total <- function(result, con, unpaged_sql) {
  if (nrow(result) > 0L) {
    total <- result$pagination_total_rows[[1]]
    result$pagination_total_rows <- NULL
    return(list(result = result, total_rows = as.integer(total)))
  }
  count_sql <- sprintf("SELECT COUNT(*) AS n FROM (%s) AS _uncounted",
                       if (is.function(unpaged_sql)) unpaged_sql() else unpaged_sql)
  list(result = result,
       total_rows = as.integer(DBI::dbGetQuery(con, count_sql)$n[[1]]))
}
