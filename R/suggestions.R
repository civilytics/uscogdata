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
  .attach_ig_counterparts(con, suggestions)
}

#' Attach `ig_recipe_id` to each suggestion: the intergovernmental-expenditure
#' recipe (an M-to-local or L-to-state recipe) whose component codes cover
#' exactly the same set of function suffixes as the firing recipe's own
#' components, e.g. `corrections_combined`'s {E04, E05} -> suffixes {"04",
#' "05"} matches `corrections_ig_local_combined`'s {M04, M05} -> the same
#' {"04", "05"}. `NULL` when no such recipe exists, which also covers the
#' case where the firing recipe already IS the IG recipe (self-matches are
#' excluded, so an IG recipe never names itself as its own counterpart).
#'
#' Matching is deliberately an exact set match, not "any suffix in common":
#' the two-digit suffix only means the same "function" across recipes that
#' share the underlying Census functional-classification scheme (E/F/G/L/M
#' all use "04"/"05" for corrections). M/L "combined other" codes (47/89/
#' 91-94) reuse digits for an unrelated catch-all construct, so e.g.
#' `general_gov_e89_wide`'s {E85, E89} -> {"85", "89"} must NOT match
#' `ige_local_m89_wide`'s {"89", "91", "92", "93"} on the shared "89" alone --
#' verified against the fixture's full `harmonization_recipes` catalog (see
#' task-6-report.md): only the corrections family (E/F/G/M, suffixes 04/05)
#' has an exact-set match in this corpus.
#' @noRd
.attach_ig_counterparts <- function(con, suggestions) {
  if (length(suggestions) == 0L) return(suggestions)

  comp <- DBI::dbGetQuery(con,
    "SELECT recipe_id, component_code FROM harmonization_recipes")
  comp$suffix <- substr(comp$component_code, 2L, nchar(comp$component_code))
  suffix_sets <- lapply(split(comp$suffix, comp$recipe_id), function(x) sort(unique(x)))

  ig_recipe_ids <- unique(
    comp$recipe_id[substr(comp$component_code, 1L, 1L) %in% c("M", "L")]
  )

  find_counterpart <- function(rid) {
    own <- suffix_sets[[rid]]
    if (is.null(own)) return(NULL)
    for (cand in ig_recipe_ids) {
      if (identical(cand, rid)) next
      if (setequal(suffix_sets[[cand]], own)) return(cand)
    }
    NULL
  }

  lapply(suggestions, function(s) {
    # `s$ig_recipe_id <- NULL` would DELETE the element rather than set it
    # (standard R list-assignment gotcha), leaving no-match entries missing
    # the key entirely instead of carrying it as NULL. Single-bracket
    # assignment with a wrapped list preserves a NULL-valued element so the
    # field is always present, per the brief's "NULL when there is none".
    s["ig_recipe_id"] <- list(find_counterpart(s$recipe_id))
    s
  })
}

#' Emit the single cli::cli_inform() message summarizing all suggestions
#' for a verb call (the brief's "one message", not one per suggestion).
#' Bullet text is pre-formatted plain text (no cli/glue `{}` markup) since
#' recipe ids/labels are untrusted-ish data values, not literal call-site
#' expressions. When a suggestion has an `ig_recipe_id`, one indented
#' continuation line is appended naming the intergovernmental counterpart
#' recipe (embedded `\n` renders as a hanging-indent continuation of the
#' same bullet under cli, not a new bullet).
#' @noRd
.inform_suggestions <- function(suggestions) {
  bullets <- vapply(suggestions, function(s) {
    bullet <- sprintf("%s (%d-%d): %s", s$recipe_id,
            s$available_years[1], s$available_years[2], s$hint)
    if (!is.null(s$ig_recipe_id)) {
      bullet <- paste0(bullet, sprintf(
        "\n  intergovernmental counterpart: recipe = '%s'", s$ig_recipe_id))
    }
    bullet
  }, character(1))
  cli::cli_inform(c(
    i = "Coverage gap detected for the requested years; a harmonization recipe may fill it:",
    stats::setNames(bullets, rep("*", length(bullets)))
  ))
}
