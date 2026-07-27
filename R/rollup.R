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
#'   to [cog_spending()]).
#' @param years Integer vector of years.
#' @param per_capita If `TRUE`, per-capita uses each gov's own per-year
#'   population from `gov_population_yearly`. Govs with missing population
#'   are excluded from the result.
#' @param adjust_to_year Integer base year for CPI-U conversion, or `NULL`.
#' @param expenditure_concept `"direct"` (default) or `"total"`. Currently only
#'   `"direct"` is accepted; the `"total"` option exists in [cog_spending()] for
#'   single-government queries but cannot be used here because combining Total
#'   across multiple layers of government double-counts intergovernmental
#'   transfers (a state's payment to a school district is the same dollar the
#'   district reports as its own Direct spending).
#' @return Tibble with columns `year`, `layer`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real` /
#'   `amt_per_capita_nominal` / `amt_per_capita_real`, optional `pop_source`,
#'   `codes_included`, `aggregate_fallback`, `scope_note`, `notes`. Carries a
#'   `provenance` attribute with `verb = "cog_geographic_rollup"`, `layers`,
#'   and `rollup$included_govids` / `rollup$excluded_govids`.
#' @export
cog_geographic_rollup <- function(govids, category, years,
                                  per_capita = FALSE, adjust_to_year = NULL,
                                  expenditure_concept = c("direct", "total")) {
  call <- match.call()
  expenditure_concept <- match.arg(expenditure_concept)
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

  r <- cog_spending(all_govids, years, category, per_capita, adjust_to_year)
  r <- dplyr::left_join(r, layer_map, by = "canonical_govid",
                        relationship = "many-to-many")
  r$scope_note <- .rollup_scope_note(r$layer)

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
