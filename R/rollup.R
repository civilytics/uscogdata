# R/rollup.R

#' Aggregate spending across state/county/city layers for a place
#'
#' Wraps [cog_spending()], tags each row with its layer, and attaches a
#' human-readable `scope_note` documenting geographic-scope caveats (e.g.
#' "county totals include areas outside the listed city"). Useful for
#' "place portraits" that compare a city to the surrounding county and
#' containing state on one set of axes.
#'
#' When `per_capita = TRUE`, rows whose government has no observed
#' population in that year (`pop_source == "unavailable"`) are dropped from
#' the result. The dropped govids are recorded in
#' `provenance$rollup$excluded_govids`. This excludes special districts
#' (gov type 4) and school districts (gov type 5) from per-capita rollups
#' by design — see `vignette('population-denominators')`.
#'
#' @param govids Named list with any non-empty subset of elements named
#'   `state`, `county`, `city`. Each element is a character vector of
#'   `canonical_govid` values. At least one layer required.
#' @param category Single category name or character vector (passed through
#'   to [cog_spending()]), or the reserved `"All Categories"` for one summed
#'   row per `(year, canonical_govid, subtype)` covering every category in the
#'   concept's scope. `"All Categories"` is the efficient way to build a
#'   geographic total: without it a caller must issue one rollup per category
#'   and sum the results themselves.
#' @param years Integer vector of years.
#' @param per_capita If `TRUE`, per-capita uses each gov's own per-year
#'   population from `gov_population_yearly`. Govs with missing population
#'   are excluded from the result.
#' @param adjust_to_year Integer base year for CPI-U conversion, or `NULL`.
#' @param expenditure_concept `"primary"` (default), `"direct"`, or
#'   `"total"` -- see [cog_spending()] for the three concepts. `"total"` is
#'   refused here because combining Total across multiple layers of
#'   government double-counts intergovernmental transfers (a state's payment
#'   to a school district is the same dollar the district reports as its own
#'   Direct spending); `"primary"` and `"direct"` combine safely.
#' @param coverage How to handle the Census of Governments survey cycle,
#'   which is a **complete census only in years ending in 2 and 7** -- every
#'   other year is a sample, and the sample varies enormously (on the bundled
#'   fixture, Wisconsin's 608-city universe reports 597 governments in FY2012
#'   and 112 in FY2019).
#'
#'   * `"all"` (default) -- every unit that reported that year. Unchanged
#'     behaviour, so existing code keeps working.
#'   * `"census"` -- census years only. Aborts if the requested range holds
#'     none, rather than silently returning nothing.
#'   * `"consistent"` -- only units reporting in *every* requested year, giving
#'     a balanced panel.
#'
#'   Regardless of mode, `provenance$coverage` always carries per-year
#'   `n_units_reporting`, `n_units_expected` and `is_census_year`, and
#'   `provenance$coverage_mode` records the mode. `is_census_year` is a
#'   statement about the **survey calendar**, never a claim of completeness:
#'   FY1967 is a census year in which only 97 of Wisconsin's 608 cities
#'   report. `n_units_reporting` is the number that tells the truth.
#' @return Tibble with columns `year`, `layer`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real` /
#'   `amt_per_capita_nominal` / `amt_per_capita_real`, optional `pop_source`,
#'   `codes_included`, `aggregate_fallback`, `scope_note`, `notes`. Carries a
#'   `provenance` attribute with `verb = "cog_geographic_rollup"`, `layers`,
#'   and `rollup$included_govids` / `rollup$excluded_govids`.
#' @export
cog_geographic_rollup <- function(govids, category, years,
                                  per_capita = FALSE, adjust_to_year = NULL,
                                  expenditure_concept = c("primary", "direct", "total"),
                                  coverage = c("all", "census", "consistent")) {
  call <- match.call()
  expenditure_concept <- match.arg(expenditure_concept)
  coverage <- .validate_coverage(coverage)
  if (identical(expenditure_concept, "total")) {
    .abort_concept_not_aggregatable("cog_geographic_rollup")
  }
  .validate_rollup_layers(govids)

  govids <- lapply(govids, .coerce_govid_input, arg = "govids[[layer]]")
  if (any(lengths(govids) == 0L)) {
    cli::cli_abort("Each layer in `govids` must be non-empty after coercion.")
  }
  layer_names <- names(govids)
  all_govids  <- unlist(govids, use.names = FALSE)
  layer_map   <- tibble::tibble(
    canonical_govid = all_govids,
    layer           = rep(layer_names, lengths(govids))
  )

  # coverage = "census" drops non-census years BEFORE the query rather than
  # after: a sample year's rows are not wanted at all, and fetching them only
  # to discard them would also let them into the coverage table.
  years <- .apply_census_years(years, coverage, "cog_geographic_rollup")

  r <- cog_spending(all_govids, years, category, per_capita, adjust_to_year,
                    expenditure_concept = expenditure_concept)
  r <- dplyr::left_join(r, layer_map, by = "canonical_govid",
                        relationship = "many-to-many")
  r$scope_note <- .rollup_scope_note(r$layer)

  if (identical(coverage, "consistent")) {
    r <- .filter_consistent(r, years)
  }

  excluded <- character(0)
  if (isTRUE(per_capita) && "pop_source" %in% names(r)) {
    drop <- r$pop_source == "unavailable"
    excluded <- unique(r$canonical_govid[drop])
    r <- r[!drop, , drop = FALSE]
  }
  included <- unique(r$canonical_govid)

  r <- .reorder_rollup_cols(r)

  prov <- attr(r, "provenance")
  prov$verb   <- "cog_geographic_rollup"
  prov$call   <- paste(deparse(call), collapse = " ")
  prov$layers <- layer_names
  prov$rollup <- list(
    included_govids = included,
    excluded_govids = excluded
  )
  # n_units_expected is the universe the CALLER named -- the govids passed in
  # -- not the national universe. That is what makes the ratio meaningful:
  # "597 of the 608 Wisconsin cities you asked about reported in FY2012".
  prov$coverage_mode <- coverage
  prov$coverage <- .coverage_table(r, years, length(unique(all_govids)))
  attr(r, "provenance") <- prov

  r
}

#' @noRd
.validate_rollup_layers <- function(govids) {
  if (!is.list(govids) || is.data.frame(govids)) {
    cli::cli_abort("`govids` must be a named list.")
  }
  if (length(govids) == 0L) {
    cli::cli_abort("`govids` must have non-zero length (at least one layer).")
  }
  nms <- names(govids)
  if (is.null(nms) || any(!nzchar(nms))) {
    cli::cli_abort("`govids` must be fully named.")
  }
  bad <- setdiff(nms, c("state", "county", "city"))
  if (length(bad) > 0L) {
    cli::cli_abort(
      "`govids` names must be one of 'state', 'county', 'city'. Got: {bad}."
    )
  }
  invisible(TRUE)
}

#' @noRd
.rollup_scope_note <- function(layer) {
  dplyr::case_when(
    layer == "state"  ~ "state total; not limited to geography served by listed city/county",
    layer == "county" ~ "county totals include areas outside the listed city",
    layer == "city"   ~ "city proper only; excludes special districts in the same county",
    TRUE ~ NA_character_
  )
}

#' @noRd
.reorder_rollup_cols <- function(r) {
  front <- c("year", "layer", "canonical_govid", "gov_name",
             "spend_subtype", "category", "amt_nominal")
  back  <- c("codes_included", "aggregate_fallback", "scope_note", "notes")
  middle <- setdiff(names(r), c(front, back))
  desired <- c(front, middle, back)
  r[, desired[desired %in% names(r)], drop = FALSE]
}
