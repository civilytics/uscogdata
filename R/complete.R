# R/complete.R
#
# `complete = TRUE` on the money verbs. Fills the requested grid so that a
# cell the corpus does not carry still appears, labelled with WHY it is
# missing.
#
# The corpus stopped storing the wide era's explicit zeros
# (cog_pipeline#64, series break SB194), which made absence ambiguous:
#
#   <= FY2011  dense_source   absent => Census published $0    (census_zero)
#   >= FY2012  sparse_source  absent => not reported, unknown  (not_reported)
#
# Before sparsification a wide-era query whose cells were all $0 came back as
# explicit $0 rows; afterwards it came back empty, with nothing to say which
# of the two meanings applied. This restores that -- and improves on it,
# because the pre-sparsification corpus could not distinguish the two either.
#
# `census_zero` fills carry `amt_nominal = 0`; `not_reported` fills carry NA.
# That difference is the entire point: writing 0 into a modern absence would
# invent data, which is the error the representation contract exists to stop.

#' @noRd
.abort_complete_unsupported <- function(reason, alternative) {
  cli::cli_abort(c(
    "{.code complete = TRUE} is not supported for this query.",
    x = reason,
    i = alternative
  ), class = "uscogdata_complete_unsupported")
}

#' @noRd
.require_representation <- function(con, manifest) {
  needed <- c("representation.parquet", "code_set.parquet")
  missing <- needed[!vapply(needed, function(f) .corpus_has_table(manifest, f),
                            logical(1))]
  if (length(missing) == 0L) return(invisible(TRUE))
  cli::cli_abort(c(
    "This corpus does not publish the representation contract.",
    x = "Missing: {.file {missing}}.",
    i = "{.code complete = TRUE} needs those tables to know whether an absent cell means Census published $0 or means the government did not report.",
    i = "They ship with corpora published from 2026-07-29 onward; re-point {.envvar USCOGDATA_URL} at a current corpus, or omit {.code complete}."
  ), class = "uscogdata_representation_unavailable")
}

#' The cells a government-year COULD carry: every code in force for that
#' government's own type, mapped through `summary_categories`, restricted to
#' the calling verb's flow prefixes and (when given) its category filter.
#'
#' Scoped by `govs_type` deliberately. Filling against the union of all types
#' would invent cells that the government can never report -- a county row for
#' "state IG transfer to school districts" -- and those inventions would then
#' be indistinguishable from real census zeros.
#'
#' `NOT cs.is_aggregate` mirrors `spending_long` / `revenue_long`, which drop
#' aggregate rows. Without it the grid would offer cells the verb structurally
#' never returns, so every one of them would fill as a phantom $0.
#' @noRd
.completion_grid_sql <- function(subtype_col, govid, years, category,
                                 flow_prefixes) {
  category_pred <- if (is.null(category)) {
    ""
  } else {
    sprintf("AND c.category IN (%s)", .sql_lit_chr(category))
  }
  sprintf(
    "SELECT DISTINCT
       cs.year,
       x.canonical_govid,
       x.gov_name,
       c.%1$s AS subtype_value,
       c.category,
       r.absence_means
     FROM code_set cs
     JOIN canonical_fips_xwalk x ON x.govs_type = cs.type
     JOIN summary_categories c   ON c.item_code = cs.item_code
     JOIN representation r       ON r.year = cs.year
     WHERE x.canonical_govid IN (%2$s)
       AND cs.year IN (%3$s)
       AND NOT cs.is_aggregate
       AND LEFT(cs.item_code, 1) IN (%4$s)
       AND c.category IS NOT NULL
       AND c.%1$s IS NOT NULL
       %5$s",
    subtype_col, .sql_lit_chr(govid),
    paste(as.integer(years), collapse = ","),
    .sql_lit_chr(flow_prefixes), category_pred
  )
}

#' Fill `result` out to the full grid, stamping `value_source` on every row.
#'
#' Returns the completed tibble with a `.completion` attribute carrying the
#' provenance block. Reported rows are passed through untouched -- filling
#' must never alter or drop what the corpus actually published.
#' @noRd
.complete_result <- function(result, con, subtype_col, govid, years, category,
                             flow_prefixes) {
  grid <- tibble::as_tibble(DBI::dbGetQuery(
    con, .completion_grid_sql(subtype_col, govid, years, category, flow_prefixes)
  ))

  result$value_source <- rep("reported", nrow(result))
  if (nrow(grid) == 0L) {
    attr(result, ".completion") <- list(
      applied = TRUE, rows_filled = 0L, absence_means = list()
    )
    return(result)
  }

  names(grid)[names(grid) == "subtype_value"] <- subtype_col
  key <- function(d) {
    paste(d$year, d$canonical_govid, d[[subtype_col]], d$category, sep = "\r")
  }
  missing <- grid[!key(grid) %in% key(result), , drop = FALSE]

  if (nrow(missing) > 0L) {
    filled <- tibble::tibble(
      year            = as.integer(missing$year),
      canonical_govid = as.character(missing$canonical_govid),
      gov_name        = as.character(missing$gov_name),
      category        = as.character(missing$category),
      # census_zero is a value Census published; not_reported is unknown and
      # must stay NA. Collapsing the two to 0 is the defect, not the fill.
      amt_nominal     = ifelse(missing$absence_means == "census_zero",
                               0, NA_real_),
      codes_included  = NA_character_,
      aggregate_fallback = NA,
      value_source    = as.character(missing$absence_means)
    )
    filled[[subtype_col]] <- as.character(missing[[subtype_col]])
    if ("notes" %in% names(result)) filled$notes <- NA_character_

    result <- dplyr::bind_rows(result, filled)
    result <- result[order(result$year, result$canonical_govid,
                           result[[subtype_col]], result$category), ,
                     drop = FALSE]
  }

  rules <- unique(grid[, c("year", "absence_means")])
  attr(result, ".completion") <- list(
    applied = TRUE,
    rows_filled = nrow(missing),
    absence_means = stats::setNames(
      as.list(as.character(rules$absence_means)), as.character(rules$year)
    )
  )
  result
}
