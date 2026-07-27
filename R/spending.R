# R/spending.R

#' Summarized spending by category
#'
#' One row per `(year, canonical_govid, spend_subtype, category)`. Amounts are
#' returned in **full U.S. dollars** (the raw corpus stores them in $1,000s;
#' this verb multiplies by 1000 so downstream code can freely rescale to
#' millions/billions). The conversion is recorded in the provenance attribute
#' under `transformations$units_conversion`.
#'
#' @param govid Character vector of `canonical_govid` values.
#' @param years Integer vector of years.
#' @param category Character vector of category names (from
#'   `summary_categories.category`), or `NULL` for all categories.
#' @param per_capita If `TRUE`, adds `amt_per_capita_nominal` (and
#'   `amt_per_capita_real` when `adjust_to_year` is set) using the per-year
#'   Census F-33 population from `gov_population_yearly`. Result also gains
#'   a `pop_source` column with values `"census_f33"` or `"unavailable"`
#'   (the latter for gov types 4/5 and any row whose population is missing
#'   in that year).
#' @param adjust_to_year Integer base year for CPI-U real-dollar conversion,
#'   or `NULL` for nominal only.
#' @param basis `"harmonized"` (default) sums item codes through the
#'   cross-vintage harmonization mapping (folding series-break-affected
#'   codes onto a comparable target and excluding aggregate / discontinued
#'   rows -- see the `harmonization` block in `cog_explain()`); `"raw"`
#'   reproduces the pre-Phase-R2 behavior (published item codes, no
#'   folding). On a corpus with `schema_version < 5` (no harmonization
#'   tables), `basis` silently resolves to `"raw"` when left at its default
#'   and the resolution is recorded in the provenance; explicitly passing
#'   `basis = "harmonized"` on such a corpus aborts. Ignored when `recipe`
#'   is set (see below).
#' @param recipe Optional harmonization recipe id (see [cog_recipes()]) for
#'   multi-code cross-vintage series that a 1:1 harmonized_code mapping
#'   can't express (e.g. a wide-era aggregate that only splits into leaf
#'   codes in the modern era). Mutually exclusive with `category`. The
#'   result's subtype column reads `"recipe"` and `category` reads the
#'   recipe's label. Requires `schema_version >= 5`. A recipe query bypasses
#'   `basis` entirely (it joins `long` directly rather than going through
#'   the `*_annotated`/`*_annotated_harmonized` views), so the `basis`
#'   argument is ignored and the result's provenance reports
#'   `basis = "recipe"` with an inert `harmonization` block (`applied =
#'   FALSE`, pointing at the `recipe` block instead) rather than a
#'   possibly-misleading `"harmonized"`/`"raw"` value.
#' @param expenditure_concept `"direct"` (default) returns only the
#'   government's own direct spending (item codes `E`/`F`/`G`), unchanged
#'   from prior releases. `"total"` additionally UNIONs in the
#'   intergovernmental leg -- payments to local governments (`M` codes) and
#'   to the state government (`L` codes, excluding the `L--` family-total
#'   rollup) -- so results gain rows with `spend_subtype ==
#'   "intergovernmental"`. Mutually exclusive with `recipe` (a recipe
#'   already defines its own component codes).
#' @return Tibble with columns `year`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real`,
#'   optional `amt_per_capita_nominal`, optional `amt_per_capita_real`,
#'   optional `pop_source`, `codes_included`, `aggregate_fallback`, `notes`.
#'   Carries a `provenance` attribute matching `inst/schemas/provenance-v1.json`.
#' @export
cog_spending <- function(govid, years, category = NULL,
                         per_capita = FALSE, adjust_to_year = NULL,
                         basis = c("harmonized", "raw"), recipe = NULL,
                         expenditure_concept = c("direct", "total")) {
  .verb_spendrev(
    verb          = "cog_spending",
    view_base     = "spending_annotated",
    subtype_col   = "spend_subtype",
    flow_prefixes = c("E", "F", "G"),
    call          = match.call(),
    govid         = govid,
    years         = years,
    category      = category,
    per_capita    = per_capita,
    adjust_to_year = adjust_to_year,
    basis         = basis,
    recipe        = recipe,
    expenditure_concept = expenditure_concept
  )
}

#' @noRd
.verb_spendrev <- function(verb, view_base, subtype_col, flow_prefixes, call,
                           govid, years, category,
                           per_capita, adjust_to_year,
                           basis = c("harmonized", "raw"), recipe = NULL,
                           expenditure_concept = c("direct", "total")) {
  basis_explicit <- length(basis) == 1L
  basis <- match.arg(basis, c("harmonized", "raw"))
  # match.arg() itself throws a base `simpleError`, not an rlang-classed
  # condition; wrap it so an invalid expenditure_concept aborts consistently
  # with the rest of this package's validation (cli::cli_abort -> rlang_error).
  expenditure_concept <- tryCatch(
    match.arg(expenditure_concept, c("direct", "total")),
    error = function(e) {
      cli::cli_abort(
        "`expenditure_concept` must be one of {.val direct} or {.val total}.",
        class = "uscogdata_invalid_expenditure_concept",
        parent = e
      )
    }
  )

  govid <- .coerce_govid_input(govid, arg = "govid")
  .validate_verb_inputs(govid, years, category, per_capita, adjust_to_year,
                        recipe)

  if (!is.null(recipe) && identical(expenditure_concept, "total")) {
    cli::cli_abort(c(
      "`recipe` and `expenditure_concept = \"total\"` are mutually exclusive.",
      i = "A recipe defines its own component codes; pass one or the other.",
      i = "For a recipe's intergovernmental counterpart, use the matching IG recipe (e.g. `corrections_ig_local_combined`)."
    ), class = "uscogdata_recipe_concept_conflict")
  }

  years   <- as.integer(years)
  if (!is.null(adjust_to_year)) adjust_to_year <- as.integer(adjust_to_year)

  con <- .ensure_session()
  manifest <- .uscogdata_env$manifest
  scope <- .check_govids_in_scope(govid)

  resolved <- .resolve_basis(basis, basis_explicit, manifest)

  recipe_block <- NULL
  category_for_prov <- category
  if (!is.null(recipe)) {
    .require_schema_v5(con, manifest, "recipe =")
    .validate_recipe_id(con, recipe)
    comps <- .recipe_components(con, recipe)
    recipe_label <- comps$label[[1]]
    result <- .run_recipe(con, recipe, govid, years)
    sql <- attr(result, "sql_query")
    result <- .shape_recipe_result(result, subtype_col, recipe_label)
    recipe_block <- list(
      recipe_id = recipe, label = recipe_label,
      components = .df_to_row_list(comps)
    )
    category_for_prov <- recipe_label
  } else {
    view <- .select_view(view_base, resolved$basis)
    ig_view <- if (identical(expenditure_concept, "total")) {
      .select_ig_view(resolved$basis)
    } else {
      NULL
    }
    sql <- .build_verb_sql(view, subtype_col, govid, years, category, ig_view)
    result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  }

  if (per_capita) result <- .attach_per_capita(result, con, govid)
  if (!is.null(adjust_to_year)) {
    result <- .attach_real_dollars(result, adjust_to_year, per_capita)
  }

  result$notes <- .notes_column(result)

  # A recipe result doesn't go through spending_annotated(_harmonized) /
  # revenue_annotated(_harmonized) at all -- .run_recipe()'s generic join
  # reads `long` directly -- so `basis` and the `harmonization` exclusion
  # count (which is itself computed from `long`, independent of which view
  # a non-recipe query used) would describe a code path this result never
  # took. Rather than report a technically-still-computed but misleading
  # basis = "harmonized"/"raw" + harmonization$applied combo, recipe
  # results report basis = "recipe" and an explicit, inert harmonization
  # block pointing at the `recipe` block instead. Task 12 (cog-api) passes
  # provenance through verbatim, so this needs to be unambiguous rather
  # than technically-defensible-but-confusing.
  if (!is.null(recipe)) {
    basis_for_prov <- "recipe"
    basis_note_for_prov <- NA_character_
    harmonization <- list(
      applied = FALSE, na_rows_excluded = 0L, na_amount_excluded = 0,
      note = "basis/harmonization not applicable to recipe results; see the recipe block instead"
    )
    suggestions <- list()
  } else {
    basis_for_prov <- resolved$basis
    basis_note_for_prov <- resolved$note
    harmonization <- .build_harmonization_block(
      con, govid, years, resolved, flow_prefixes
    )
    suggestions <- .build_suggestions(con, govid, years, category, result, resolved$basis)
  }

  prov <- .build_provenance(
    verb           = verb,
    call           = call,
    govid          = govid,
    years          = years,
    category       = category_for_prov,
    per_capita     = per_capita,
    adjust_to_year = adjust_to_year,
    result         = result,
    sql            = sql,
    subtype_col    = subtype_col,
    basis          = basis_for_prov,
    basis_note     = basis_note_for_prov,
    harmonization  = harmonization,
    recipe         = recipe_block,
    suggestions    = suggestions
  )
  prov$scope$govids_found   <- scope$found
  prov$scope$govids_missing <- scope$missing
  attr(result, "provenance") <- prov
  attr(result, ".popyear_range") <- NULL

  if (length(suggestions) > 0L) .inform_suggestions(suggestions)

  result
}

#' @noRd
.validate_verb_inputs <- function(govid, years, category,
                                  per_capita, adjust_to_year, recipe = NULL) {
  if (!is.character(govid) || length(govid) == 0L) {
    cli::cli_abort("`govid` must be a non-empty character vector.")
  }
  if (!(is.integer(years) || is.numeric(years)) || length(years) == 0L) {
    cli::cli_abort("`years` must be a non-empty integer vector.")
  }
  if (!is.null(category) && !is.character(category)) {
    cli::cli_abort("`category` must be character or NULL.")
  }
  if (!is.logical(per_capita) || length(per_capita) != 1L) {
    cli::cli_abort("`per_capita` must be a length-1 logical.")
  }
  if (!is.null(adjust_to_year)) {
    if (!(is.integer(adjust_to_year) || is.numeric(adjust_to_year)) ||
        length(adjust_to_year) != 1L) {
      cli::cli_abort("`adjust_to_year` must be NULL or a length-1 integer.")
    }
  }
  if (!is.null(recipe)) {
    if (!is.character(recipe) || length(recipe) != 1L) {
      cli::cli_abort("`recipe` must be NULL or a length-1 character string.")
    }
    if (!is.null(category)) {
      cli::cli_abort(c(
        "`recipe` and `category` are mutually exclusive.",
        i = "Pass one or the other, not both."
      ), class = "uscogdata_recipe_category_conflict")
    }
  }
  invisible(TRUE)
}

#' @noRd
.select_view <- function(view_base, basis) {
  if (identical(basis, "harmonized")) paste0(view_base, "_harmonized") else view_base
}

#' @noRd
.select_ig_view <- function(basis) {
  if (identical(basis, "harmonized")) "ig_annotated_harmonized" else "ig_annotated"
}

#' @noRd
.sql_lit_chr <- function(x) {
  safe <- gsub("'", "''", x, fixed = TRUE)
  paste0("'", safe, "'", collapse = ",")
}

#' @noRd
.build_verb_sql <- function(view, subtype_col, govid, years, category,
                            ig_view = NULL) {
  govid_lit <- .sql_lit_chr(govid)
  years_lit <- paste(as.integer(years), collapse = ",")
  category_pred <- if (is.null(category)) {
    ""
  } else {
    sprintf("AND category IN (%s)", .sql_lit_chr(category))
  }

  # expenditure_concept = "total" adds the intergovernmental leg. UNION ALL,
  # never UNION: the two legs are disjoint by item_code prefix (E/F/G vs M/L),
  # so de-duplication would be pure cost, and a silent row-drop if two
  # governments ever reported identical values.
  source_expr <- if (is.null(ig_view)) {
    view
  } else {
    sprintf("(SELECT * FROM %s UNION ALL SELECT * FROM %s)", view, ig_view)
  }

  sprintf(
    "SELECT
       year,
       canonical_govid,
       COALESCE(xwalk_gov_name, gov_name) AS gov_name,
       %1$s,
       category,
       SUM(amt) * 1000.0 AS amt_nominal,
       string_agg(DISTINCT item_code, ',' ORDER BY item_code) AS codes_included,
       bool_and(is_aggregate) AS aggregate_fallback
     FROM %2$s
     WHERE canonical_govid IN (%3$s)
       AND year IN (%4$s)
       %5$s
     GROUP BY year, canonical_govid, gov_name, xwalk_gov_name, %1$s, category
     ORDER BY year, canonical_govid, %1$s, category",
    subtype_col, source_expr, govid_lit, years_lit, category_pred
  )
}

#' @noRd
.attach_per_capita <- function(result, con, govid) {
  if (nrow(result) == 0L) {
    result$amt_per_capita_nominal <- numeric(0)
    result$pop_source <- character(0)
    attr(result, ".popyear_range") <- integer(0)
    return(result)
  }
  years_lit <- paste(unique(as.integer(result$year)), collapse = ",")
  sql <- sprintf(
    "SELECT canonical_govid, year, population, popyear
     FROM gov_population_yearly
     WHERE canonical_govid IN (%s)
       AND year IN (%s)",
    .sql_lit_chr(govid), years_lit
  )
  pops <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  result <- dplyr::left_join(result, pops,
                             by = c("canonical_govid", "year"))
  result$amt_per_capita_nominal <- result$amt_nominal / result$population
  result$pop_source <- ifelse(is.na(result$population),
                              "unavailable", "census_f33")
  py <- result$popyear[!is.na(result$popyear)]
  attr(result, ".popyear_range") <- if (length(py) > 0L) {
    as.integer(c(min(py), max(py)))
  } else {
    integer(0)
  }
  result$population <- NULL
  result$popyear <- NULL
  result
}

#' @noRd
.attach_real_dollars <- function(result, adjust_to_year, per_capita) {
  if (nrow(result) == 0L) {
    result$amt_real <- numeric(0)
    if (per_capita) result$amt_per_capita_real <- numeric(0)
    return(result)
  }
  result$amt_real <- .inflate(result$amt_nominal, result$year, adjust_to_year)
  if (per_capita && "amt_per_capita_nominal" %in% names(result)) {
    result$amt_per_capita_real <- .inflate(
      result$amt_per_capita_nominal, result$year, adjust_to_year
    )
  }
  result
}

#' @noRd
.notes_column <- function(result) {
  n <- nrow(result)
  if (n == 0L) return(character(0))
  parts <- vector("list", 2L)
  agg <- result[["aggregate_fallback"]]
  parts[[1]] <- if (!is.null(agg)) {
    ifelse(agg %in% TRUE,
           "Aggregate fallback applied; see cog_explain()",
           NA_character_)
  } else {
    rep(NA_character_, n)
  }
  ps <- result[["pop_source"]]
  parts[[2]] <- if (!is.null(ps)) {
    ifelse(ps == "unavailable",
           "No population denominator available for this gov type",
           NA_character_)
  } else {
    rep(NA_character_, n)
  }
  out <- character(n)
  for (i in seq_len(n)) {
    pieces <- vapply(parts, `[[`, character(1), i)
    pieces <- pieces[!is.na(pieces)]
    out[i] <- if (length(pieces) == 0L) "" else paste(pieces, collapse = "; ")
  }
  out
}
