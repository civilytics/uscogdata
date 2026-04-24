# R/provenance.R
# Shared provenance construction. Matches inst/schemas/provenance-v1.json.

#' @noRd
.build_provenance <- function(verb, call, govid, years, category,
                              per_capita, adjust_to_year, result, sql,
                              subtype_col) {
  manifest <- .uscogdata_env$manifest

  codes <- result[["codes_included"]]
  codes_observed <- if (length(codes) == 0L) {
    character(0)
  } else {
    sorted <- sort(unique(unlist(strsplit(codes, ",", fixed = TRUE))))
    sorted[nzchar(sorted)]
  }

  agg_flag <- result[["aggregate_fallback"]]
  agg_applied <- isTRUE(any(agg_flag, na.rm = TRUE))
  agg_years <- if (agg_applied) {
    unique(as.integer(result$year[which(agg_flag)]))
  } else {
    integer(0)
  }

  gov_names <- if (nrow(result) == 0L) {
    character(0)
  } else {
    unique(result$gov_name)
  }

  list(
    verb = verb,
    call = paste(deparse(call), collapse = " "),
    target = list(
      canonical_govid = as.character(govid),
      gov_name = gov_names
    ),
    years = as.integer(years),
    category = category,
    scope = list(
      gov_types_included = as.integer(unlist(manifest$scope$gov_types_included)),
      gov_types_excluded = as.integer(unlist(manifest$scope$gov_types_excluded)),
      scope_note = manifest$scope$scope_note %||% ""
    ),
    codes_summed = list(
      observed = codes_observed,
      subtype_column = subtype_col
    ),
    aggregate_fallback = list(
      applied = agg_applied,
      years = agg_years
    ),
    transformations = list(
      units_conversion = list(
        applied = TRUE,
        source_unit = "$1,000s (raw Census)",
        target_unit = "$USD",
        multiplier = 1000L
      ),
      per_capita = list(
        applied = isTRUE(per_capita),
        denominator_source = if (isTRUE(per_capita)) {
          "ACS 2018-2022 B01003_001 (population_acs from canonical_fips_xwalk)"
        } else {
          NA_character_
        }
      ),
      inflation = list(
        applied = !is.null(adjust_to_year),
        base_year = if (is.null(adjust_to_year)) NA_integer_ else as.integer(adjust_to_year),
        index = if (is.null(adjust_to_year)) NA_character_ else "CPI-U (BLS CPIAUCSL annual average, bundled)"
      )
    ),
    series_break_refs = character(0),
    manifest = list(
      schema_version = as.integer(manifest$schema_version),
      pipeline_commit = manifest$pipeline_commit %||% NA_character_,
      built_at = manifest$built_at %||% NA_character_
    ),
    sql_query = sql
  )
}
