# R/fiscal.R
#
# Fiscal-year timing (uscogdata#77). The corpus's `year` is the Census SURVEY
# year, and one survey year covers different calendar months for different
# governments. Census's rule (Local Government Finance FAQ, Q6): survey year Y
# holds each government's fiscal year that ENDED between July 1 of Y-1 and
# June 30 of Y. `long.fiscal_year_end` (an MMDD integer such as 630 or 1231)
# says which months that is for a given government-year.
#
# Two kinds of government follow a different rule: survey year Y holds the
# fiscal year ending in calendar year Y, even when that is after June 30.
#
#   * State governments (type 0). Census's 2004 and 2006 technical
#     documentation names the Alabama and Michigan (September 30) and Texas
#     (August 31) state governments as exceptions "included as though they
#     were part of the June 30 group". The published corpus agrees in two
#     survey years (measurements in uscogdata#77):
#       - 2020: those three states' federal aid jumps with the CARES Act in
#         2020, as the June-30 states' does, while New York (March 31) and 15
#         large September-30 cities and counties jump in 2021.
#       - 2009: their federal aid jumps with the 2009 stimulus in survey year
#         2009 and slows in 2011, as the June-30 states' does. Under the plain
#         rule their 2009 would end in 2008, before the stimulus, and their
#         2011 would be the full stimulus year. The same 15 local governments
#         jump in 2011, as the plain rule predicts for them.
#     For the other 47 states both rules give the same months.
#   * The District of Columbia (type 2 here), which the same documentation
#     lists with the September-30 exceptions. The 2009 and 2020 data each
#     neither confirm nor rule this out, so it rests on the documentation
#     alone.

# canonical_govids that follow the state-government rule without being type 0.
.SURVEY_YEAR_SAME_YEAR_GOVIDS <- c(
  "112001124214"  # Washington, D.C.
)

#' Days in a month, vectorized over year and month.
#' @noRd
.days_in_month <- function(year, month) {
  dim <- c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)
  leap <- (year %% 4L == 0L & year %% 100L != 0L) | year %% 400L == 0L
  out <- dim[month]
  out[month == 2L & leap] <- 29L
  out
}

#' Build Dates from year/month/day, clamping the day to the month's length
#' (so a February 29 year end falls on February 28 in a common year).
#' @noRd
.make_date <- function(year, month, day) {
  out <- rep(as.Date(NA), length(year))
  ok <- !is.na(year) & !is.na(month) & !is.na(day)
  if (any(ok)) {
    d <- pmin(day[ok], .days_in_month(year[ok], month[ok]))
    out[ok] <- as.Date(sprintf("%04d-%02d-%02d", year[ok], month[ok], d))
  }
  out
}

#' TRUE where `fiscal_year_end` is a usable MMDD value.
#' @noRd
.valid_fiscal_year_end <- function(fye) {
  fye <- as.integer(fye)
  m <- fye %/% 100L
  d <- fye %% 100L
  ok <- !is.na(fye) & !is.na(m) & m >= 1L & m <= 12L & d >= 1L
  ok[ok] <- d[ok] <= .days_in_month(2000L, m[ok])  # 2000 is a leap year
  ok
}

#' The fiscal period a survey year covers for one government-year.
#'
#' Vectorized over its arguments, which must have equal length.
#'
#' @param year Integer survey year (the corpus's `year`).
#' @param fiscal_year_end Integer MMDD from `long.fiscal_year_end`.
#' @param gov_type Integer government type (0 = state).
#' @param canonical_govid Character canonical id.
#' @return List of Date vectors `period_start` and `period_end`; `NA` where
#'   `fiscal_year_end` is missing or not a valid MMDD.
#' @noRd
.survey_period <- function(year, fiscal_year_end, gov_type, canonical_govid) {
  year <- as.integer(year)
  fye <- as.integer(fiscal_year_end)
  ok <- .valid_fiscal_year_end(fye)
  month <- fye %/% 100L
  day <- fye %% 100L

  same_year <- (!is.na(gov_type) & as.integer(gov_type) == 0L) |
    canonical_govid %in% .SURVEY_YEAR_SAME_YEAR_GOVIDS
  end_year <- ifelse(same_year | month <= 6L, year, year - 1L)

  month[!ok] <- NA_integer_
  # The period starts the day after the same month-day one year earlier,
  # which is when the government's previous fiscal year ended.
  list(
    period_start = .make_date(end_year - 1L, month, day) + 1L,
    period_end   = .make_date(end_year, month, day)
  )
}

#' Look up each government-year's fiscal_year_end and type in `long`.
#'
#' A government-year whose rows carry more than one distinct value gets `NA`
#' rather than an arbitrary pick. None does in the fixture's four years.
#'
#' @return Tibble with `canonical_govid`, `year` (integer), `gov_type`
#'   (integer) and `fiscal_year_end` (integer), one row per government-year
#'   found in the corpus.
#' @noRd
.fiscal_year_lookup <- function(con, govids, years) {
  govids <- unique(govids[!is.na(govids) & nzchar(govids)])
  years <- unique(as.integer(years[!is.na(years)]))
  if (length(govids) == 0L || length(years) == 0L) {
    return(tibble::tibble(canonical_govid = character(0), year = integer(0),
                          gov_type = integer(0),
                          fiscal_year_end = integer(0)))
  }
  out <- tibble::as_tibble(DBI::dbGetQuery(con, sprintf(
    "SELECT canonical_govid, year,
            MIN(type) AS gov_type,
            CASE WHEN COUNT(DISTINCT fiscal_year_end) = 1
                 THEN MAX(fiscal_year_end) END AS fiscal_year_end
     FROM long
     WHERE canonical_govid IN (%s) AND year IN (%s)
     GROUP BY canonical_govid, year",
    .sql_lit_chr(govids), paste(years, collapse = ",")
  )))
  out$year <- as.integer(out$year)
  out$gov_type <- as.integer(out$gov_type)
  out$fiscal_year_end <- as.integer(out$fiscal_year_end)
  out
}

#' Fiscal-year columns for every (canonical_govid, year) pair, in input order.
#' @return Tibble with `fiscal_year_end`, `period_start`, `period_end`.
#' @noRd
.fiscal_periods_for <- function(con, govids, years) {
  years <- as.integer(years)
  fy <- .fiscal_year_lookup(con, govids, years)
  idx <- match(paste(govids, years), paste(fy$canonical_govid, fy$year))
  fye <- fy$fiscal_year_end[idx]
  per <- .survey_period(years, fye, fy$gov_type[idx], govids)
  tibble::tibble(
    fiscal_year_end = ifelse(.valid_fiscal_year_end(fye), fye, NA_integer_),
    period_start = per$period_start,
    period_end   = per$period_end
  )
}

#' Append `fiscal_year_end`, `period_start` and `period_end` to a verb result.
#'
#' Joined by position rather than with `dplyr::left_join()`, so row order and
#' the result's attributes are untouched. Rows with no `canonical_govid`
#' (none today) get `NA`.
#' @noRd
.attach_fiscal_period <- function(result, con) {
  if (nrow(result) == 0L) {
    result$fiscal_year_end <- integer(0)
    result$period_start <- as.Date(character(0))
    result$period_end <- as.Date(character(0))
    return(result)
  }
  fp <- .fiscal_periods_for(con, as.character(result$canonical_govid),
                            result$year)
  result$fiscal_year_end <- fp$fiscal_year_end
  result$period_start <- fp$period_start
  result$period_end <- fp$period_end
  result
}

#' Provenance block recorded when a verb is called with `fiscal_period = TRUE`.
#' Absent otherwise, so default output keeps its existing shape.
#' @noRd
.fiscal_period_provenance <- function(result) {
  list(
    applied = TRUE,
    source = "long.fiscal_year_end (MMDD), per government-year",
    rule = paste(
      "Survey year Y covers the fiscal year that ended between July 1 of Y-1",
      "and June 30 of Y; state governments and the District of Columbia",
      "cover the fiscal year ending in calendar year Y."
    ),
    rows_without_period = sum(is.na(result$period_end))
  )
}

#' @noRd
.validate_fiscal_period_arg <- function(fiscal_period) {
  if (!is.logical(fiscal_period) || length(fiscal_period) != 1L ||
      is.na(fiscal_period)) {
    cli::cli_abort("{.arg fiscal_period} must be {.code TRUE} or {.code FALSE}.")
  }
  invisible(fiscal_period)
}

#' Fiscal-year periods behind survey years
#'
#' Returns the calendar months each survey year covers for each government.
#' The corpus's `year` is the Census survey year, and a survey year covers
#' different months for different governments.
#'
#' @section The survey-year rule:
#' Census assigns each government's fiscal year to a survey year by when the
#' fiscal year ended. Survey year Y holds the fiscal year that ended between
#' July 1 of Y-1 and June 30 of Y. The corpus records each government-year's
#' fiscal year end as `fiscal_year_end`, an MMDD integer such as `630` or
#' `1231`.
#'
#' Survey year 2017 therefore covers, for a county, city or township:
#'
#'   * `fiscal_year_end = 630` (June 30): the fiscal year ending June 30,
#'     2017, so July 2016 to June 2017.
#'   * `930` (September 30): the fiscal year ending September 30, 2016, so
#'     October 2015 to September 2016.
#'   * `1231` (December 31): the fiscal year ending December 31, 2016, so
#'     January to December 2016.
#'
#' A city with a December year end and a city with a June year end are both
#' "2017" in the corpus, but their figures are six months apart. A September
#' year end is nine months behind a June one.
#'
#' State governments (type 0) follow a different rule: survey year Y holds the
#' fiscal year ending in calendar year Y. For Alabama and Michigan (September
#' 30) that means October 2016 to September 2017, and for Texas (August 31)
#' September 2016 to August 2017. Census's 2004 and 2006 technical
#' documentation lists these three states as exceptions to the June 30 window,
#' and the corpus agrees in survey years 2009 and 2020, the two years checked:
#' their federal aid moves with the 2009 stimulus and the 2020 CARES Act in
#' the same survey years as the June 30 states' does. The same documentation
#' lists the District of Columbia, so it is treated the same way. Checks
#' against the 2009 and 2020 data were inconclusive for it, so that treatment
#' rests on the documentation alone. For New York (March 31) and the 46 states
#' with a June 30 year end, the two rules give the same months.
#'
#' A government can change its fiscal year end, so the periods are looked up
#' per government-year. Where the corpus has no `fiscal_year_end` for a
#' government-year, or the government has no rows that year, the period is
#' `NA`. Most of FY1993 is `NA`: 99% of its government-years have no usable
#' value in the public corpus as of November 2026. So do 5% to 11% in FY1978
#' and FY1987 to FY1990, and under 3% in every other year.
#'
#' From FY2023 the source files mark some rows as estimates carried forward
#' from an earlier year. The periods here describe the survey year, not the
#' year a carried-forward row's data pertain to.
#'
#' @param govid Character vector of `canonical_govid` values, or a data frame
#'   with a `canonical_govid` column.
#' @param years Integer vector of survey years.
#' @return Tibble with one row per requested government and year, in the
#'   order `govid` x `years`: `canonical_govid`, `year`, `fiscal_year_end`
#'   (integer MMDD), `period_start` and `period_end` (Dates, inclusive).
#' @seealso [cog_survey_year()] for the reverse mapping; the `fiscal_period`
#'   argument of [cog_spending()], [cog_revenue()] and [cog_balances()] to get
#'   the same columns on every row.
#' @examples
#' \dontrun{
#' # A June 30 state, a September 30 state and a September 30 county
#' cog_fiscal_periods(
#'   c("130000226087", "010000226085", "121011212191"),
#'   years = 2020
#' )
#' }
#' @export
cog_fiscal_periods <- function(govid, years) {
  if (missing(govid)) cli::cli_abort("{.arg govid} is required.")
  if (missing(years)) cli::cli_abort("{.arg years} is required.")
  govid <- .coerce_govid_input(govid, arg = "govid")
  if (length(govid) == 0L || anyNA(govid) || !all(nzchar(govid))) {
    cli::cli_abort("{.arg govid} must name at least one government, with no missing or empty ids.")
  }
  if (!is.numeric(years) || length(years) == 0L || anyNA(years)) {
    cli::cli_abort("{.arg years} must be a non-empty integer vector with no missing values.")
  }
  govid <- unique(govid)
  years <- unique(as.integer(years))

  con <- .ensure_session()
  grid <- expand.grid(year = years, canonical_govid = govid,
                      stringsAsFactors = FALSE)
  fp <- .fiscal_periods_for(con, grid$canonical_govid, grid$year)
  tibble::tibble(
    canonical_govid = grid$canonical_govid,
    year = as.integer(grid$year),
    fiscal_year_end = fp$fiscal_year_end,
    period_start = fp$period_start,
    period_end = fp$period_end
  )
}

#' Survey year that covers a calendar date for a government
#'
#' Maps a date to the survey year whose fiscal period, for that government,
#' contains it. This is the reverse of [cog_fiscal_periods()]: use it to place
#' an event that happened on a known date against the corpus's `year`.
#'
#' The date can fall in survey year Y, Y+1 or Y+2 of its own calendar year Y,
#' depending on the government's fiscal year end. Each candidate is looked up
#' with the `fiscal_year_end` the corpus records for that government-year, so
#' a change of fiscal year is respected. When the government has no rows, or
#' no `fiscal_year_end`, in the survey year that would cover the date, the
#' result is `NA`; the function does not borrow another year's value. If a
#' change of fiscal year makes two survey years' periods overlap, the earlier
#' survey year is returned.
#'
#' @inheritSection cog_fiscal_periods The survey-year rule
#' @param govid Character vector of `canonical_govid` values, or a data frame
#'   with a `canonical_govid` column.
#' @param date Dates, or character strings in `"YYYY-MM-DD"` form. `govid`
#'   and `date` must have the same length, or one of them must have length 1.
#' @return Tibble with one row per (`govid`, `date`) pair, in input order:
#'   `canonical_govid`, `date`, `year` (the survey year, `NA` when it cannot
#'   be determined), `fiscal_year_end`, `period_start` and `period_end`.
#' @seealso [cog_fiscal_periods()]
#' @examples
#' \dontrun{
#' # April 15, 2020 for a September 30 county and a September 30 state
#' cog_survey_year(c("121011212191", "010000226085"), as.Date("2020-04-15"))
#' }
#' @export
cog_survey_year <- function(govid, date) {
  if (missing(govid)) cli::cli_abort("{.arg govid} is required.")
  if (missing(date)) cli::cli_abort("{.arg date} is required.")
  govid <- .coerce_govid_input(govid, arg = "govid")
  if (length(govid) == 0L || anyNA(govid) || !all(nzchar(govid))) {
    cli::cli_abort("{.arg govid} must name at least one government, with no missing or empty ids.")
  }
  date <- .coerce_date_input(date)
  n <- max(length(govid), length(date))
  if (!length(govid) %in% c(1L, n) || !length(date) %in% c(1L, n)) {
    cli::cli_abort(c(
      "{.arg govid} and {.arg date} must have the same length, or one must have length 1.",
      "x" = "{.arg govid} has length {length(govid)}; {.arg date} has length {length(date)}."
    ))
  }
  govid <- rep_len(govid, n)
  date <- rep_len(date, n)

  con <- .ensure_session()
  cal_year <- as.integer(format(date, "%Y"))
  cand <- data.frame(
    i = rep(seq_len(n), each = 3L),
    canonical_govid = rep(govid, each = 3L),
    year = rep(cal_year, each = 3L) + rep(0:2, times = n),
    stringsAsFactors = FALSE
  )
  cand <- cand[!is.na(cand$year), , drop = FALSE]
  fp <- .fiscal_periods_for(con, cand$canonical_govid, cand$year)
  cand <- cbind(cand, fp)
  d <- date[cand$i]
  hit <- !is.na(cand$period_start) & d >= cand$period_start &
    d <= cand$period_end
  cand <- cand[hit, , drop = FALSE]
  cand <- cand[order(cand$i, cand$year), , drop = FALSE]
  first <- cand[!duplicated(cand$i), , drop = FALSE]
  idx <- match(seq_len(n), first$i)

  tibble::tibble(
    canonical_govid = govid,
    date = date,
    year = as.integer(first$year[idx]),
    fiscal_year_end = first$fiscal_year_end[idx],
    period_start = first$period_start[idx],
    period_end = first$period_end[idx]
  )
}

#' Coerce `date` to Date, refusing values that do not parse.
#' @noRd
.coerce_date_input <- function(date) {
  if (length(date) == 0L) cli::cli_abort("{.arg date} must not be empty.")
  if (inherits(date, "POSIXt")) date <- as.Date(date)
  if (!inherits(date, "Date")) {
    if (!is.character(date)) {
      cli::cli_abort("{.arg date} must be a Date or a character vector of dates.")
    }
    parsed <- as.Date(date, format = "%Y-%m-%d")
    bad <- !is.na(date) & is.na(parsed)
    if (any(bad)) {
      cli::cli_abort(c(
        "{.arg date} has values that are not dates.",
        "x" = "Could not parse: {.val {unique(date[bad])}}."
      ))
    }
    date <- parsed
  }
  date
}
