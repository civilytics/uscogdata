# R/adjust.R
# Inflation adjustment helpers using bundled CPIAUCSL annual averages.
# The `cpi_annual` tibble (year, cpi) is stored as internal data in
# R/sysdata.rda and built via data-raw/ on package update.

#' Return the bundled annual CPI table.
#'
#' @return Tibble with columns `year` (integer) and `cpi` (numeric, CPIAUCSL
#'   annual average, 1982-84 = 100).
#' @noRd
.cpi_table <- function() {
  cpi_annual
}

#' Inflate (or deflate) an amount vector between two years.
#'
#' Converts nominal amounts in `from_year` dollars to real amounts in
#' `to_year` dollars using the bundled CPIAUCSL annual average index.
#' Multiplies by `cpi[to_year] / cpi[from_year]`.
#'
#' @param amt Numeric vector of nominal amounts.
#' @param from_year Integer or integer-like vector of source years (one per
#'   element of `amt`, or length 1).
#' @param to_year Integer target year (scalar).
#' @return Numeric vector of real amounts, same length as `amt`.
#' @noRd
.inflate <- function(amt, from_year, to_year) {
  cpi <- .cpi_table()
  from_year <- as.integer(from_year)
  to_year   <- as.integer(to_year)
  if (length(to_year) != 1L) {
    cli::cli_abort("`to_year` must be a scalar.")
  }
  if (!(to_year %in% cpi$year)) {
    cli::cli_abort("CPI unavailable for to_year = {to_year}. Supported: {min(cpi$year)}-{max(cpi$year)}.")
  }
  missing_years <- setdiff(from_year[!is.na(from_year)], cpi$year)
  if (length(missing_years) > 0) {
    cli::cli_abort("CPI unavailable for from_year value(s): {missing_years}.")
  }
  lookup <- stats::setNames(cpi$cpi, as.character(cpi$year))
  cpi_from <- unname(lookup[as.character(from_year)])
  cpi_to   <- unname(lookup[as.character(to_year)])
  amt * cpi_to / cpi_from
}
