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
#'   `amt_per_capita_real` when `adjust_to_year` is set) using the per-year
#'   Census F-33 population from `gov_population_yearly`. Result also gains
#'   a `pop_source` column with values `"census_f33"` or `"unavailable"`
#'   (the latter for gov types 4/5 and any row whose population is missing
#'   in that year).
#' @param adjust_to_year Integer base year for CPI-U real-dollar conversion,
#'   or `NULL` for nominal only.
#' @return Tibble with columns `year`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real`,
#'   optional `amt_per_capita_nominal`, optional `amt_per_capita_real`,
#'   optional `pop_source`, `codes_included`, `aggregate_fallback`, `notes`.
#'   Carries a `provenance` attribute matching `inst/schemas/provenance-v1.json`.
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
  govid <- .coerce_govid_input(govid, arg = "govid")
  .validate_verb_inputs(govid, years, category, per_capita, adjust_to_year)

  years   <- as.integer(years)
  if (!is.null(adjust_to_year)) adjust_to_year <- as.integer(adjust_to_year)

  con <- .ensure_session()
  scope <- .check_govids_in_scope(govid)

  sql <- .build_verb_sql(view, subtype_col, govid, years, category)
  result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))

  if (per_capita) result <- .attach_per_capita(result, con, govid)
  if (!is.null(adjust_to_year)) {
    result <- .attach_real_dollars(result, adjust_to_year, per_capita)
  }

  result$notes <- .notes_column(result)

  prov <- .build_provenance(
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
  prov$scope$govids_found   <- scope$found
  prov$scope$govids_missing <- scope$missing
  attr(result, "provenance") <- prov
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
    result$pop_source <- character(0)
    return(result)
  }
  years_lit <- paste(unique(as.integer(result$year)), collapse = ",")
  sql <- sprintf(
    "SELECT canonical_govid, year, population
     FROM gov_population_yearly
     WHERE canonical_govid IN (%s)
       AND year IN (%s)",
    .sql_lit_chr(govid), years_lit
  )
  pops <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  result <- dplyr::left_join(result, pops,
                             by = c("canonical_govid", "year"))
  result$amt_per_capita_nominal <- result$amt_nominal / result$population
  result$pop_source <- ifelse(is.na(result$population),
                              "unavailable", "census_f33")
  result$population <- NULL
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
  n <- nrow(result)
  if (n == 0L) return(character(0))
  parts <- vector("list", 2L)
  agg <- result[["aggregate_fallback"]]
  parts[[1]] <- ifelse(
    !is.null(agg) & isTRUE(any(agg, na.rm = TRUE)) & agg %in% TRUE,
    "Aggregate fallback applied; see cog_explain()",
    NA_character_
  )
  ps <- result[["pop_source"]]
  parts[[2]] <- if (!is.null(ps)) {
    ifelse(ps == "unavailable",
           "No population denominator available for this gov type",
           NA_character_)
  } else {
    rep(NA_character_, n)
  }
  out <- character(n)
  for (i in seq_len(n)) {
    pieces <- vapply(parts, `[[`, character(1), i)
    pieces <- pieces[!is.na(pieces)]
    out[i] <- if (length(pieces) == 0L) "" else paste(pieces, collapse = "; ")
  }
  out
}
