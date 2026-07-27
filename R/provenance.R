# R/provenance.R
# Shared provenance construction. Matches inst/schemas/provenance-v1.json.

#' @noRd
.build_provenance <- function(verb, call, govid, years, category,
                              per_capita, adjust_to_year, result, sql,
                              subtype_col, basis = NA_character_,
                              basis_note = NA_character_,
                              expenditure_concept = "direct",
                              expenditure_concept_note = NA_character_,
                              expenditure_concept_direct_suppressed = FALSE,
                              harmonization = NULL, recipe = NULL,
                              suggestions = list()) {
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

  schema_version <- suppressWarnings(as.integer(manifest$schema_version %||% 0L))
  con <- .uscogdata_env$con
  break_refs <- if (!is.null(con) && DBI::dbIsValid(con)) {
    .build_series_break_refs(con, codes_observed, years, schema_version)
  } else {
    character(0)
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
    basis = basis,
    basis_note = basis_note,
    expenditure_concept = expenditure_concept,
    expenditure_concept_note = expenditure_concept_note,
    expenditure_concept_direct_suppressed = isTRUE(expenditure_concept_direct_suppressed),
    harmonization = harmonization %||% list(
      applied = FALSE, na_rows_excluded = 0L, na_amount_excluded = 0,
      note = NA_character_
    ),
    recipe = recipe,
    suggestions = suggestions,
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
          "Census F-33 population (per-year, from long.population)"
        } else {
          NA_character_
        },
        popyear_range = if (isTRUE(per_capita)) {
          attr(result, ".popyear_range") %||% integer(0)
        } else {
          integer(0)
        },
        pop_source_counts = if (isTRUE(per_capita)) {
          ps <- result[["pop_source"]]
          if (is.null(ps) || length(ps) == 0L) {
            list(census_f33 = 0L, unavailable = 0L)
          } else {
            list(
              census_f33  = sum(ps == "census_f33", na.rm = TRUE),
              unavailable = sum(ps == "unavailable", na.rm = TRUE)
            )
          }
        } else {
          NULL
        }
      ),
      inflation = list(
        applied = !is.null(adjust_to_year),
        base_year = if (is.null(adjust_to_year)) NA_integer_ else as.integer(adjust_to_year),
        index = if (is.null(adjust_to_year)) NA_character_ else "CPI-U (BLS CPIAUCSL annual average, bundled)"
      )
    ),
    series_break_refs = break_refs,
    manifest = list(
      schema_version = as.integer(manifest$schema_version),
      pipeline_commit = manifest$pipeline_commit %||% NA_character_,
      built_at = manifest$built_at %||% NA_character_
    ),
    sql_query = sql
  )
}
