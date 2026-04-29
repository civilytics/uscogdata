# R/explain.R

#' Explain a verb result's provenance
#'
#' Prints the structured provenance attached to a tibble returned by any
#' `cog_*` verb, or returns it as a list for downstream use (MCP tools,
#' dashboards, JSON export).
#'
#' @param result A tibble returned by a `cog_*` verb.
#' @param format `"print"` (default) for a human-readable cli summary;
#'   returns `result` invisibly for chaining. `"list"` returns the raw
#'   provenance list (identical to `attr(result, "provenance")`).
#' @return Either `result` (invisibly) or the provenance list.
#' @export
cog_explain <- function(result, format = c("print", "list")) {
  format <- match.arg(format)
  prov <- attr(result, "provenance")
  if (is.null(prov)) {
    cli::cli_abort(c(
      "No `provenance` attribute on result.",
      i = "Pass a tibble returned by a cog_* verb (e.g. cog_spending())."
    ))
  }
  if (format == "list") return(prov)
  .print_provenance(prov)
  invisible(result)
}

#' @noRd
.print_provenance <- function(prov) {
  cli::cli_h1("{prov$verb}()")

  tgt_ids   <- paste(prov$target$canonical_govid, collapse = ", ")
  tgt_names <- if (length(prov$target$gov_name) == 0L) {
    "(no rows returned)"
  } else {
    paste(prov$target$gov_name, collapse = ", ")
  }
  cli::cli_text("Target: {tgt_names} [canonical_govid: {tgt_ids}]")

  yrs <- prov$years
  cli::cli_text(if (length(yrs) == 1L) {
    "Year: {yrs}"
  } else {
    "Years: {min(yrs)}-{max(yrs)} ({length(yrs)} years)"
  })

  if (!is.null(prov$category)) {
    cli::cli_text("Category: {paste(prov$category, collapse = ', ')}")
  } else {
    cli::cli_text("Category: (all)")
  }

  cli::cli_h2("Codes observed")
  codes <- prov$codes_summed$observed
  if (length(codes) == 0L) {
    cli::cli_alert_info("No item codes matched.")
  } else {
    cli::cli_ul(codes)
  }

  if (isTRUE(prov$aggregate_fallback$applied)) {
    cli::cli_h2("Aggregate fallback")
    cli::cli_alert_warning(
      "Aggregate fallback used for years: {paste(prov$aggregate_fallback$years, collapse = ', ')}"
    )
  }

  cli::cli_h2("Transformations")
  uc <- prov$transformations$units_conversion
  if (isTRUE(uc$applied)) {
    cli::cli_text("Units: {uc$source_unit} -> {uc$target_unit} (x{uc$multiplier})")
  }
  pc <- prov$transformations$per_capita
  if (isTRUE(pc$applied)) {
    cli::cli_text("Per-capita denominator: {pc$denominator_source}")
    if (length(pc$popyear_range) == 2L) {
      cli::cli_text(
        "  popyear range: {pc$popyear_range[1]}-{pc$popyear_range[2]}"
      )
    }
    if (!is.null(pc$pop_source_counts)) {
      cli::cli_text(
        "  pop_source counts: census_f33={pc$pop_source_counts$census_f33}, unavailable={pc$pop_source_counts$unavailable}"
      )
    }
  }
  infl <- prov$transformations$inflation
  if (isTRUE(infl$applied)) {
    cli::cli_text("Inflation: {infl$index}, base year {infl$base_year}")
  }

  cli::cli_h2("Scope")
  cli::cli_text(
    "Included gov types: {paste(prov$scope$gov_types_included, collapse = ', ')}"
  )
  cli::cli_text(
    "Excluded gov types: {paste(prov$scope$gov_types_excluded, collapse = ', ')}"
  )
  if (nzchar(prov$scope$scope_note %||% "")) {
    cli::cli_text("Note: {prov$scope$scope_note}")
  }

  cli::cli_h2("Data vintage")
  cli::cli_text(
    "Manifest schema v{prov$manifest$schema_version}, pipeline {prov$manifest$pipeline_commit}, built {prov$manifest$built_at}"
  )

  invisible(NULL)
}
