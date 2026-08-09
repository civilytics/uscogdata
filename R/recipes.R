# R/recipes.R
# Harmonization recipes: multi-code, cross-vintage series built by summing a
# fixed set of component item codes with per-component weights and
# year/gov-type scoping (see the `harmonization_recipes` view, registered
# from data/harmonization_recipes.parquet, schema_version >= 5 only).
#
# Recipes exist because some cross-vintage series can't be expressed as a
# 1:1 harmonized_code mapping (basis = "harmonized"): the wide era (pre-2012)
# publishes only a combined aggregate row for these families (e.g.
# corrections functions 04+05), while the modern era splits them into leaf
# codes. A recipe's generic join sums whichever of its component codes are
# present for a given year, so the resulting series is continuous across
# that format boundary.

#' List available harmonization recipes
#'
#' Recipes are multi-code cross-vintage series (see [cog_spending()]'s
#' `recipe` argument) catalogued in the corpus's `harmonization_recipes`
#' table. Use this to discover valid `recipe` ids.
#'
#' @param pattern Optional regex matched case-insensitively against
#'   `recipe_id` or `label`.
#' @return Tibble with columns `recipe_id`, `label`, `n_components`,
#'   `year_min`, `year_max` (the min/max component year coverage), sorted by
#'   `recipe_id`.
#' @export
cog_recipes <- function(pattern = NULL) {
  if (!is.null(pattern) &&
      (!is.character(pattern) || length(pattern) != 1L)) {
    cli::cli_abort("`pattern` must be a length-1 character string or NULL.")
  }
  con <- .ensure_session()
  .require_schema_v5(con, .uscogdata_env$manifest, "cog_recipes()")

  where <- if (is.null(pattern)) {
    ""
  } else {
    sprintf(
      "WHERE regexp_matches(recipe_id, %1$s, 'i') OR regexp_matches(label, %1$s, 'i')",
      .sql_lit_chr(pattern)
    )
  }
  sql <- paste(
    "SELECT recipe_id, any_value(label) AS label,
            COUNT(*) AS n_components,
            MIN(year_min) AS year_min, MAX(year_max) AS year_max
     FROM harmonization_recipes",
    where,
    "GROUP BY recipe_id
     ORDER BY recipe_id"
  )
  out <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  out$year_min <- as.integer(out$year_min)
  out$year_max <- as.integer(out$year_max)
  out$n_components <- as.integer(out$n_components)
  out
}

#' Abort unless the active corpus has schema_version >= 5.
#' @noRd
.require_schema_v5 <- function(con, manifest, what) {
  sv <- suppressWarnings(as.integer(manifest$schema_version %||% 0L))
  if (sv < 5L) {
    cli::cli_abort(c(
      sprintf("%s requires corpus schema_version >= 5.", what),
      x = "Active corpus has schema_version {sv}.",
      i = "Point USCOGDATA_URL at a schema_version >= 5 corpus to use harmonization recipes."
    ), class = "uscogdata_schema_unsupported")
  }
  invisible(sv)
}

#' Abort with the valid id list unless `recipe_id` exists in the catalog.
#' @noRd
.validate_recipe_id <- function(con, recipe_id) {
  ids <- DBI::dbGetQuery(
    con, "SELECT DISTINCT recipe_id FROM harmonization_recipes"
  )$recipe_id
  if (!recipe_id %in% ids) {
    cli::cli_abort(c(
      "Unknown recipe = {.val {recipe_id}}.",
      i = "Valid ids: {paste(sort(ids), collapse = ', ')}",
      i = "See cog_recipes() for labels and year coverage."
    ), class = "uscogdata_unknown_recipe")
  }
  invisible(TRUE)
}

#' Fetch the component rows for one recipe (label, component codes, scope,
#' year ranges, weights) -- both for running the recipe and for the
#' `recipe` provenance block.
#' @noRd
.recipe_components <- function(con, recipe_id) {
  sql <- sprintf(
    "SELECT recipe_id, label, component_code, gov_type_scope,
            year_min, year_max, weight, source_break_ids, notes
     FROM harmonization_recipes
     WHERE recipe_id = %s
     ORDER BY component_code",
    .sql_lit_chr(recipe_id)
  )
  tibble::as_tibble(DBI::dbGetQuery(con, sql))
}

#' Run a recipe's generic join: sum `amt * weight` across whichever
#' component codes are present for each (year, canonical_govid), scoped by
#' gov_type_scope. Deliberately does NOT filter `NOT is_aggregate`: in the
#' wide era (<= 2011) these families' component codes exist ONLY as
#' aggregate rows (leaves first appear 2012), so excluding aggregates would
#' zero out the wide-era half of every recipe. This is safe by corpus
#' construction -- wide-era rows for these codes are aggregate-only, modern
#' rows are leaf-only, and every component row is year-scoped via
#' `year_min`/`year_max` -- so there is no double-counting. (Checkpoint
#' review docs/phase_r_harmonization_review.md § 0.2.)
#' @noRd
.run_recipe <- function(con, recipe_id, cohort, years) {
  sql <- sprintf(
    "SELECT l.year, l.canonical_govid,
            COALESCE(x.gov_name, l.gov_name) AS gov_name,
            SUM(l.amt * r.weight) * 1000.0 AS amt_nominal,
            string_agg(DISTINCT l.item_code, ',' ORDER BY l.item_code) AS codes_included
     FROM long l
     JOIN harmonization_recipes r
       ON l.item_code = r.component_code
      AND l.year BETWEEN r.year_min AND r.year_max
      AND (r.gov_type_scope = 'all'
           OR (r.gov_type_scope = 'state' AND l.type = 0)
           OR (r.gov_type_scope = 'local' AND l.type BETWEEN 1 AND 3))
     LEFT JOIN canonical_fips_xwalk x USING (canonical_govid)
     WHERE r.recipe_id = %1$s
       AND %2$s
       AND l.year IN (%3$s)
     GROUP BY 1, 2, 3
     ORDER BY 1, 2",
    .sql_lit_chr(recipe_id), .cohort_sql(cohort, "l.canonical_govid"),
    paste(as.integer(years), collapse = ",")
  )
  result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  attr(result, "sql_query") <- sql
  result
}

#' Shape a raw .run_recipe() result into the standard cog_spending()/
#' cog_revenue() column layout: subtype = "recipe", category = the recipe's
#' label, aggregate_fallback = FALSE (recipes resolve coverage gaps by
#' construction, not by falling back to an aggregate row).
#' @noRd
.shape_recipe_result <- function(result, subtype_col, label) {
  sql_query <- attr(result, "sql_query")
  n <- nrow(result)
  result[[subtype_col]] <- rep("recipe", n)
  result$category <- rep(label, n)
  result$aggregate_fallback <- rep(FALSE, n)
  result <- result[, c(
    "year", "canonical_govid", "gov_name", subtype_col, "category",
    "amt_nominal", "codes_included", "aggregate_fallback"
  ), drop = FALSE]
  attr(result, "sql_query") <- sql_query
  result
}

#' Turn a small data.frame into a list-of-lists (one list per row), the
#' shape used for the `recipe$components` provenance block.
#' @noRd
.df_to_row_list <- function(df) {
  lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
}
