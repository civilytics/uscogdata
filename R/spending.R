# R/spending.R

#' Summarized spending by category
#'
#' One row per `(year, canonical_govid, spend_subtype, category)`. Amounts are
#' returned in **full U.S. dollars** (the raw corpus stores them in $1,000s;
#' this verb multiplies by 1000 so downstream code can freely rescale to
#' millions/billions). The conversion is recorded in the provenance attribute
#' under `transformations$units_conversion`.
#'
#' @param govid Character vector of `canonical_govid` values.
#' @param years Integer vector of years.
#' @param category Character vector of category names (from
#'   `summary_categories.category`), or `NULL` for all categories.
#' @param per_capita If `TRUE`, adds `amt_per_capita_nominal` (and
#'   `amt_per_capita_real` when `adjust_to_year` is set) using
#'   `population_acs` from the canonical xwalk.
#' @param adjust_to_year Integer base year for CPI-U real-dollar conversion,
#'   or `NULL` for nominal only.
#' @return Tibble with columns `year`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real`,
#'   optional `amt_per_capita_nominal`, optional `amt_per_capita_real`,
#'   `codes_included`, `aggregate_fallback`, `notes`. Carries a `provenance`
#'   attribute matching `inst/schemas/provenance-v1.json`.
#' @export
cog_spending <- function(govid, years, category = NULL,
                         per_capita = FALSE, adjust_to_year = NULL) {
  .verb_spendrev(
    verb          = "cog_spending",
    view          = "spending_annotated",
    subtype_col   = "spend_subtype",
    call          = match.call(),
    govid         = govid,
    years         = years,
    category      = category,
    per_capita    = per_capita,
    adjust_to_year = adjust_to_year
  )
}

#' @noRd
.verb_spendrev <- function(verb, view, subtype_col, call,
                           govid, years, category,
                           per_capita, adjust_to_year) {
  .validate_verb_inputs(govid, years, category, per_capita, adjust_to_year)

  govid   <- as.character(govid)
  years   <- as.integer(years)
  if (!is.null(adjust_to_year)) adjust_to_year <- as.integer(adjust_to_year)

  con <- .ensure_session()

  sql <- .build_verb_sql(view, subtype_col, govid, years, category)
  result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))

  if (per_capita) result <- .attach_per_capita(result, con, govid)
  if (!is.null(adjust_to_year)) {
    result <- .attach_real_dollars(result, adjust_to_year, per_capita)
  }

  result$notes <- .notes_column(result)

  attr(result, "provenance") <- .build_provenance(
    verb           = verb,
    call           = call,
    govid          = govid,
    years          = years,
    category       = category,
    per_capita     = per_capita,
    adjust_to_year = adjust_to_year,
    result         = result,
    sql            = sql,
    subtype_col    = subtype_col
  )
  result
}

#' @noRd
.validate_verb_inputs <- function(govid, years, category,
                                  per_capita, adjust_to_year) {
  if (!is.character(govid) || length(govid) == 0L) {
    cli::cli_abort("`govid` must be a non-empty character vector.")
  }
  if (!(is.integer(years) || is.numeric(years)) || length(years) == 0L) {
    cli::cli_abort("`years` must be a non-empty integer vector.")
  }
  if (!is.null(category) && !is.character(category)) {
    cli::cli_abort("`category` must be character or NULL.")
  }
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

#' @noRd
.sql_lit_chr <- function(x) {
  safe <- gsub("'", "''", x, fixed = TRUE)
  paste0("'", safe, "'", collapse = ",")
}

#' @noRd
.build_verb_sql <- function(view, subtype_col, govid, years, category) {
  govid_lit <- .sql_lit_chr(govid)
  years_lit <- paste(as.integer(years), collapse = ",")
  category_pred <- if (is.null(category)) {
    ""
  } else {
    sprintf("AND category IN (%s)", .sql_lit_chr(category))
  }

  sprintf(
    "SELECT
       year,
       canonical_govid,
       COALESCE(xwalk_gov_name, gov_name) AS gov_name,
       %1$s,
       category,
       SUM(amt) * 1000.0 AS amt_nominal,
       string_agg(DISTINCT item_code, ',' ORDER BY item_code) AS codes_included,
       bool_and(is_aggregate) AS aggregate_fallback
     FROM %2$s
     WHERE canonical_govid IN (%3$s)
       AND year IN (%4$s)
       %5$s
     GROUP BY year, canonical_govid, gov_name, xwalk_gov_name, %1$s, category
     ORDER BY year, canonical_govid, %1$s, category",
    subtype_col, view, govid_lit, years_lit, category_pred
  )
}

#' @noRd
.attach_per_capita <- function(result, con, govid) {
  if (nrow(result) == 0L) {
    result$amt_per_capita_nominal <- numeric(0)
    return(result)
  }
  sql <- sprintf(
    "SELECT canonical_govid, population_acs
     FROM canonical_fips_xwalk
     WHERE canonical_govid IN (%s)",
    .sql_lit_chr(govid)
  )
  pops <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  result <- dplyr::left_join(result, pops, by = "canonical_govid")
  result$amt_per_capita_nominal <- result$amt_nominal / result$population_acs
  result$population_acs <- NULL
  result
}

#' @noRd
.attach_real_dollars <- function(result, adjust_to_year, per_capita) {
  if (nrow(result) == 0L) {
    result$amt_real <- numeric(0)
    if (per_capita) result$amt_per_capita_real <- numeric(0)
    return(result)
  }
  result$amt_real <- .inflate(result$amt_nominal, result$year, adjust_to_year)
  if (per_capita && "amt_per_capita_nominal" %in% names(result)) {
    result$amt_per_capita_real <- .inflate(
      result$amt_per_capita_nominal, result$year, adjust_to_year
    )
  }
  result
}

#' @noRd
.notes_column <- function(result) {
  if (nrow(result) == 0L) return(character(0))
  ifelse(
    isTRUE(result$aggregate_fallback) | result$aggregate_fallback %in% TRUE,
    "Aggregate fallback applied; see cog_explain()",
    ""
  )
}
