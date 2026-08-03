# R/balance_caveats.R
#
# The four caveats from cog_pipeline/docs/data_dictionary.md § Cash and
# security holdings. Each one silently invalidates an obvious analysis, so
# they travel in provenance (machine-readable, for cog-api#26) rather than
# living only in prose.
#
# Two of the four are already carried by the code-driven series-break
# builders and are deliberately NOT duplicated here:
#   * SB195/SB196 -- X40/X41 book -> market at FY2002 -- fire via
#     series_break_refs on the recipe path, the only path that observes those
#     codes.
# What remains is the GAAP distinction (a constant) and the coverage windows
# (measured, never hardcoded, so they stay correct as the corpus grows).

#' Per-subtype observed year extents, plus which requested families are
#' truncated relative to the requested span.
#' @noRd
.balance_caveats <- function(con, codes_observed, years) {
  cw <- .balance_coverage_windows(con)

  observed_subtypes <- if (length(codes_observed) == 0L) {
    character(0)
  } else {
    DBI::dbGetQuery(con, sprintf(
      "SELECT DISTINCT balance_subtype FROM summary_categories
       WHERE item_code IN (%s) AND balance_subtype IS NOT NULL",
      .sql_lit_chr(codes_observed)
    ))$balance_subtype
  }

  # A family is "truncated" when the caller asked for years outside the span
  # that family actually covers -- the FY2016 employee-retirement termination
  # and the FY2021 end of the W family are both this shape.
  truncated <- character(0)
  if (length(years) > 0L) {
    for (s in observed_subtypes) {
      w <- cw[[s]]
      if (is.null(w)) next
      if (max(years) > w[2] || min(years) < w[1]) truncated <- c(truncated, s)
    }
  }

  list(
    not_gaap = TRUE,
    not_gaap_note = paste0(
      "Census holdings are gross -- no liabilities are netted -- and are NOT ",
      "GAAP fund balance. A reserve ratio built from them overstates what is ",
      "actually available."
    ),
    coverage_window = cw,
    truncated = sort(unique(truncated))
  )
}

#' Per-subtype [min year, max year] extents for EVERY balance subtype in the
#' mounted corpus, memoised for the session.
#'
#' The query carries no govid and no year predicate -- its answer is a property
#' of the mounted corpus alone and cannot change between calls -- but it scans
#' the whole of `balance_long`, which measured 35% of `cog_balances()` runtime
#' on the bundled fixture and would be a per-request throughput ceiling once
#' cog-api#26 serves this verb over HTTP. Memoised in `.uscogdata_env` and
#' invalidated by `cog_close()`, the same pattern as `.uscogdata_env$manifest`.
#'
#' Scope is deliberately corpus-wide rather than query-scoped: a caller asking
#' "is there a family I missed?" needs every window. The observed-scoped field
#' is `truncated`. Documented as such in inst/schemas/provenance-v1.json.
#' @noRd
.balance_coverage_windows <- function(con) {
  cached <- .uscogdata_env$balance_coverage_windows
  if (!is.null(cached)) return(cached)

  windows <- DBI::dbGetQuery(con,
    "SELECT c.balance_subtype AS subtype,
            MIN(l.year) AS year_min,
            MAX(l.year) AS year_max
     FROM balance_long l
     JOIN summary_categories c USING (item_code)
     WHERE c.balance_subtype IS NOT NULL
     GROUP BY 1
     ORDER BY 1"
  )

  cw <- stats::setNames(
    lapply(seq_len(nrow(windows)),
           function(i) as.integer(c(windows$year_min[i], windows$year_max[i]))),
    windows$subtype
  )
  .uscogdata_env$balance_coverage_windows <- cw
  cw
}

#' TRUE the first time `key` is seen this session, FALSE thereafter.
#' Reset by cog_close().
#' @noRd
.balance_caveat_once <- function(key) {
  seen <- .uscogdata_env$balance_caveats_shown
  if (is.null(seen)) seen <- character(0)
  if (key %in% seen) return(FALSE)
  .uscogdata_env$balance_caveats_shown <- c(seen, key)
  TRUE
}

#' Emit at most one message per caveat class per session.
#' @noRd
.emit_balance_caveats <- function(caveats) {
  if (.balance_caveat_once("not_gaap")) {
    cli::cli_inform(c(
      "!" = "Census holdings are gross and are {.strong not} GAAP fund balance.",
      "i" = "No liabilities are netted; a reserve ratio built from them overstates available funds."
    ))
  }
  if (length(caveats$truncated) > 0L &&
      .balance_caveat_once("coverage_window")) {
    cli::cli_inform(c(
      "!" = "Requested years extend beyond what {.val {caveats$truncated}} actually covers.",
      "i" = "See {.code provenance$balance_caveats$coverage_window}."
    ))
  }
  invisible(NULL)
}
