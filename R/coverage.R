# R/coverage.R
#
# Reporting-coverage disclosure for the multi-government verbs (uscogdata#13,
# findings F-020 and F-023).
#
# The Census of Governments is a COMPLETE CENSUS only in years ending in 2 and
# 7. Every other year is a sample, and the sample varies enormously: on the
# bundled fixture, Wisconsin's 608-city universe reports 597 governments in
# FY2012 and 112 in FY2019. Summing "whatever reported" across those years is
# what the verbs have always done -- correctly -- but the return value said
# nothing about it, so a statewide total resting on 18% of the universe looked
# exactly like one resting on 98%.
#
# Owner's settled design: a `coverage` argument selecting WHICH units to
# include, plus always-on metadata saying how many there were either way. The
# principle behind it: using these verbs correctly must not require the caller
# to know the survey calendar.

# Years ending in 2 or 7 are full censuses of every government; all others are
# samples.
.CENSUS_YEAR_ENDINGS <- c(2L, 7L)

#' @noRd
.is_census_year <- function(years) {
  as.integer(years) %% 10L %in% .CENSUS_YEAR_ENDINGS
}

#' @noRd
.validate_coverage <- function(coverage) {
  tryCatch(
    match.arg(coverage, c("all", "census", "consistent")),
    error = function(e) {
      cli::cli_abort(
        "`coverage` must be one of {.val all}, {.val census} or {.val consistent}.",
        class = "uscogdata_invalid_coverage", parent = e
      )
    }
  )
}

#' Restrict `years` to census years for `coverage = "census"`.
#'
#' Aborts rather than returning an empty result when the requested range holds
#' no census year: silently handing back zero rows for a query the caller
#' believes they made is the failure mode this whole issue is about.
#' @noRd
.apply_census_years <- function(years, coverage, verb) {
  if (!identical(coverage, "census")) return(as.integer(years))
  keep <- as.integer(years)[.is_census_year(years)]
  if (length(keep) == 0L) {
    cli::cli_abort(c(
      "{.code coverage = \"census\"} leaves no years to query.",
      x = "None of the requested years end in 2 or 7: {.val {sort(unique(as.integer(years)))}}.",
      i = "Census of Governments years ending in 2 or 7 are complete censuses; all others are samples.",
      i = "Use {.code coverage = \"all\"} (the default) to keep every requested year, or request a census year."
    ), class = "uscogdata_no_census_years")
  }
  sort(keep)
}

#' Keep only units that report in EVERY requested year (a balanced panel).
#'
#' `id_col` is the government identifier; `keep_ids` are rows exempt from the
#' filter (the peer-comparison target, which is the subject of the comparison
#' rather than a member of the cohort being balanced).
#' @noRd
.filter_consistent <- function(result, years, id_col = "canonical_govid",
                               keep_ids = character(0)) {
  years <- unique(as.integer(years))
  if (nrow(result) == 0L || length(years) <= 1L) return(result)
  ids <- setdiff(unique(result[[id_col]]), c(NA, keep_ids))
  present <- vapply(ids, function(g) {
    all(years %in% unique(as.integer(result$year[result[[id_col]] == g])))
  }, logical(1))
  consistent <- c(ids[present], keep_ids)
  result[result[[id_col]] %in% consistent | is.na(result[[id_col]]), ,
         drop = FALSE]
}

#' Per-year coverage metadata, always attached regardless of mode.
#'
#' Built from the REQUESTED years rather than the years present in the result,
#' so a year in which nothing reported still appears -- with
#' `n_units_reporting = 0`, which is precisely the disclosure a silently
#' missing year fails to make.
#'
#' Three counters are returned, each answering a different question:
#'
#'   * `n_units_expected` -- the universe the caller named (govids passed in,
#'     or peers for cog_peer_compare). "How many governments did you ask
#'     about?"
#'   * `n_units_collected` -- how many of those appear in the corpus at all
#'     that year, in ANY category. This is a statement about survey collection,
#'     independent of what was asked for: "of the governments you named, how
#'     many did Census actually collect data from this year?" It separates
#'     sampling (not collected) from real zeros (collected but spends nothing
#'     in your category).
#'   * `n_units_reporting` -- how many of those appear with rows for the
#'     SPECIFIC category you requested. This is always <= n_units_collected:
#'     a government can be collected but have no rows for "Police" because it
#'     contracts policing to the county sheriff, not because it wasn't
#'     surveyed.
#'
#' `n_units_reporting` therefore conflates two very different things: a unit
#' that was not collected (sampling) and a unit that was collected but spends
#' nothing in that category. The ratio n_units_collected / n_units_expected is
#' the true collection rate; n_units_reporting / n_units_collected measures
#' category participation among collected units.
#'
#' `is_census_year` is a statement about the SURVEY CALENDAR, never a claim of
#' completeness: FY1967 is a census year in which only 97 of Wisconsin's 608
#' cities report. The counters are what tell the truth.
#'
#' @param con Active DuckDB connection (used to look up n_units_collected).
#' @param long_view The verb's own long view, used for the collection query;
#'   NULL skips the lookup and leaves n_units_collected as NA_integer_.
#' @param expected_ids The full EXPECTED cohort (govids the caller named),
#'   used as the candidate list for the collection query. Required alongside
#'   `con`/`long_view` for a correct count -- see the note below on why it
#'   must not be derived from `result`/`rows`. `NULL`, or non-`NULL` but
#'   empty after dropping `NA`/`""` entries, skips the lookup and leaves
#'   n_units_collected as NA_integer_.
#' @noRd
.coverage_table <- function(result, years, n_expected,
                            id_col = "canonical_govid", rows = NULL,
                            con = NULL, long_view = NULL,
                            expected_ids = NULL) {
  years <- sort(unique(as.integer(years)))
  src <- if (is.null(rows)) result else rows
  reporting <- vapply(years, function(y) {
    ids <- src[[id_col]][as.integer(src$year) == y]
    length(unique(ids[!is.na(ids)]))
  }, integer(1))

  # n_units_collected: count EXPECTED cohort members present in the corpus
  # for ANY category that year, not just the requested one. This separates
  # sampling (not collected at all) from real zeros (collected but no rows
  # for this category). Only computed when a connection, long_view, AND
  # expected_ids are all provided; otherwise NA_integer_.
  #
  # The candidate list MUST be expected_ids, not derived from `result`/
  # `rows`: a government with zero rows in the requested category across
  # EVERY requested year never appears in `result` at all, so deriving
  # candidates from it would silently exclude exactly the "collected but
  # real zero" governments this counter exists to count -- collapsing
  # n_units_collected back to n_units_reporting for precisely the case #36
  # was filed over.
  if (!is.null(con) && !is.null(long_view) && length(expected_ids) > 0L) {
    cohort_chr <- .sql_lit_chr(unique(expected_ids[!is.na(expected_ids) &
                                                       nzchar(expected_ids)]))
    years_lit <- paste(years, collapse = ",")
    collected_q <- sprintf(
      "SELECT year, COUNT(DISTINCT canonical_govid) AS n
       FROM %s
       WHERE canonical_govid IN (%s)
         AND year IN (%s)
       GROUP BY year",
      long_view, cohort_chr, years_lit
    )
    collected_df <- DBI::dbGetQuery(con, collected_q)
    collected_map <- setNames(collected_df$n, as.integer(collected_df$year))
    collected <- vapply(years, function(y) {
      val <- collected_map[as.character(y)]
      if (is.na(val)) 0L else as.integer(val)
    }, integer(1))
  } else {
    collected <- rep(NA_integer_, length(years))
  }

  tibble::tibble(
    year              = years,
    n_units_collected = collected,
    n_units_reporting = as.integer(reporting),
    n_units_expected  = rep(as.integer(n_expected), length(years)),
    is_census_year    = .is_census_year(years)
  )
}
