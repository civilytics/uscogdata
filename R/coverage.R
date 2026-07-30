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
#' `n_units_reporting` describes the result the caller actually received, so
#' under `coverage = "consistent"` it reports the balanced count. `is_census_year`
#' is a statement about the SURVEY CALENDAR, never a claim of completeness:
#' FY1967 is a census year in which only 97 of Wisconsin's 608 cities report.
#' `n_units_reporting` is the number that tells the truth.
#' @noRd
.coverage_table <- function(result, years, n_expected,
                            id_col = "canonical_govid", rows = NULL) {
  years <- sort(unique(as.integer(years)))
  src <- if (is.null(rows)) result else rows
  reporting <- vapply(years, function(y) {
    ids <- src[[id_col]][as.integer(src$year) == y]
    length(unique(ids[!is.na(ids)]))
  }, integer(1))
  tibble::tibble(
    year              = years,
    n_units_reporting = as.integer(reporting),
    n_units_expected  = rep(as.integer(n_expected), length(years)),
    is_census_year    = .is_census_year(years)
  )
}
