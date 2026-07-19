# R/suggestions.R
# Recipe-component-driven signposting: when a basis = "harmonized" query for
# a category comes back with a coverage gap in some requested years (the
# result has no rows at all in that year) that a harmonization recipe would
# actually fill for this government, surface that recipe as a suggestion.
#
# This is deliberately keyed off the recipe catalog's component codes, not
# off harmonization_map rows: no live map row carries a non-blank
# suggested_recipe_id (the corpus's wide era exposes split families like
# corrections functions 04+05 ONLY as aggregate rows, which basis =
# "harmonized" excludes by construction -- there's no NA ruling to hang a
# suggestion off of, just a leaf-code absence a recipe happens to fill).
# See docs/phase_r_harmonization_review.md § 0.3.
#
# Scope is deliberately narrow: signposting only runs when the caller
# supplied a `category` (an un-scoped, all-categories query has no single
# coverage question to answer) and only flags a recipe when the ACTUAL
# result has zero rows in a requested year AND the candidate recipe's own
# generic join (same join .run_recipe() uses, including its wide-era
# aggregate rows) produces at least one row for this government in that
# year. Checking presence per-government (not corpus-wide) avoids false
# positives from ordinary reporting variance -- most governments don't use
# every sibling code in a multi-code category every year, and that is not
# a format-boundary gap worth signposting.

#' Build the `prov$suggestions` list for a (non-recipe) basis = "harmonized"
#' verb call: recipes whose generic join would fill a real gap in `result`.
#'
#' @param con Active DuckDB connection.
#' @param govid Character vector of canonical_govid values (the verb's raw
#'   `govid`).
#' @param years Integer vector of requested years.
#' @param category `category` argument as passed to the verb (character
#'   vector or `NULL`; suggestions are only computed when non-NULL).
#' @param result The verb's already-computed result tibble (post basis
#'   query, pre per_capita/adjust_to_year).
#' @param basis The *resolved* basis (`"harmonized"` or `"raw"`).
#' @return List of `list(recipe_id, label, available_years, hint)`, possibly
#'   empty.
#' @noRd
.build_suggestions <- function(con, govid, years, category, result, basis) {
  if (!identical(basis, "harmonized") || is.null(category)) return(list())

  candidates <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT recipe_id FROM harmonization_recipes
     WHERE component_code IN (
       SELECT DISTINCT item_code FROM summary_categories WHERE category IN (%s)
     )",
    .sql_lit_chr(category)
  ))$recipe_id
  if (length(candidates) == 0L) return(list())

  result_years <- if (is.null(result) || nrow(result) == 0L) {
    integer(0)
  } else {
    unique(as.integer(result$year))
  }
  gap_years <- setdiff(as.integer(years), result_years)
  if (length(gap_years) == 0L) return(list())

  meta <- tibble::as_tibble(DBI::dbGetQuery(con, sprintf(
    "SELECT recipe_id, any_value(label) AS label,
            MIN(year_min) AS year_min, MAX(year_max) AS year_max
     FROM harmonization_recipes
     WHERE recipe_id IN (%s)
     GROUP BY recipe_id",
    .sql_lit_chr(candidates)
  )))

  # Which (recipe_id, year) pairs the recipe's own generic join actually
  # covers for this government, restricted to the gap years -- the same
  # join .run_recipe() uses (component year_min/year_max + gov_type_scope,
  # no is_aggregate filter), just checking existence instead of summing.
  covered <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT r.recipe_id, l.year
     FROM long l
     JOIN harmonization_recipes r
       ON l.item_code = r.component_code
      AND l.year BETWEEN r.year_min AND r.year_max
      AND (r.gov_type_scope = 'all'
           OR (r.gov_type_scope = 'state' AND l.type = 0)
           OR (r.gov_type_scope = 'local' AND l.type BETWEEN 1 AND 3))
     WHERE r.recipe_id IN (%s)
       AND l.canonical_govid IN (%s)
       AND l.year IN (%s)",
    .sql_lit_chr(candidates), .sql_lit_chr(govid),
    paste(gap_years, collapse = ",")
  ))

  suggestions <- list()
  for (rid in candidates) {
    if (!rid %in% covered$recipe_id) next
    m <- meta[meta$recipe_id == rid, ]
    suggestions[[length(suggestions) + 1L]] <- list(
      recipe_id = rid,
      label = m$label[[1]],
      available_years = c(as.integer(m$year_min), as.integer(m$year_max)),
      hint = sprintf("re-run with recipe = '%s'", rid)
    )
  }
  suggestions
}

#' Emit the single cli::cli_inform() message summarizing all suggestions
#' for a verb call (the brief's "one message", not one per suggestion).
#' Bullet text is pre-formatted plain text (no cli/glue `{}` markup) since
#' recipe ids/labels are untrusted-ish data values, not literal call-site
#' expressions.
#' @noRd
.inform_suggestions <- function(suggestions) {
  bullets <- vapply(suggestions, function(s) {
    sprintf("%s (%d-%d): %s", s$recipe_id,
            s$available_years[1], s$available_years[2], s$hint)
  }, character(1))
  cli::cli_inform(c(
    i = "Coverage gap detected for the requested years; a harmonization recipe may fill it:",
    stats::setNames(bullets, rep("*", length(bullets)))
  ))
}
