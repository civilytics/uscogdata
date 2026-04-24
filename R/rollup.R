# R/rollup.R

#' Aggregate spending across state/county/city layers for a place
#'
#' Wraps [cog_spending()], tags each row with its layer, and attaches a
#' human-readable `scope_note` documenting geographic-scope caveats (e.g.
#' "county totals include areas outside the listed city"). Useful for
#' "place portraits" that compare a city to the surrounding county and
#' containing state on one set of axes.
#'
#' @param govids Named list with any non-empty subset of elements named
#'   `state`, `county`, `city`. Each element is a character vector of
#'   `canonical_govid` values. At least one layer required.
#' @param category Single category name or character vector (passed through
#'   to [cog_spending()]).
#' @param years Integer vector of years.
#' @param per_capita If `TRUE`, per-capita uses each layer's own population
#'   from `canonical_fips_xwalk.population_acs`.
#' @param adjust_to_year Integer base year for CPI-U conversion, or `NULL`.
#' @return Tibble with columns `year`, `layer`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real` /
#'   `amt_per_capita_nominal` / `amt_per_capita_real`, `codes_included`,
#'   `aggregate_fallback`, `scope_note`, `notes`. Carries a `provenance`
#'   attribute with `verb = "cog_geographic_rollup"` and `layers`.
#' @export
cog_geographic_rollup <- function(govids, category, years,
                                  per_capita = FALSE, adjust_to_year = NULL) {
  call <- match.call()
  .validate_rollup_layers(govids)

  # Accept character vector OR a data.frame with canonical_govid per layer,
  # so cog_gov_search() output can be piped into one of the layer slots.
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
  r <- .reorder_rollup_cols(r)

  prov <- attr(r, "provenance")
  prov$verb   <- "cog_geographic_rollup"
  prov$call   <- paste(deparse(call), collapse = " ")
  prov$layers <- layer_names
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
