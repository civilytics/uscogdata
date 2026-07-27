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
#'   "intergovernmental"`. Requires the active corpus's `summary_categories`
#'   to carry M/L rows (added by cog_pipeline PR #59); aborts with class
#'   `uscogdata_ig_categories_unsupported` on an older corpus rather than
#'   silently under-reporting. Mutually exclusive with `recipe` (a recipe
#'   already defines its own component codes). **Do not sum `"total"`
#'   results across levels of government** (e.g. state + county + city):
#'   a state's `M12` payment to a school district is the same dollar the
#'   district reports as its own direct `E12`, so summing both double-counts
#'   it. This matters in particular with [cog_geographic_rollup()], which
#'   sums across exactly that kind of multi-layer government set.
#'
#'   In the legacy wide era (<= FY2011), some functions are published ONLY
#'   as an aggregate-flagged family total (e.g. Corrections' `E04`/`E05`
#'   split), which the Direct leg excludes by construction but the IG leg
#'   deliberately keeps (see `inst/sql/24-ig_long.sql`). For a `"total"`
#'   query, any (year, category) where this leaves intergovernmental rows
#'   with NO Direct counterpart is flagged: the affected rows' `notes`
#'   name the harmonization recipe that recovers the missing Direct
#'   component (when one exists), and
#'   `provenance$expenditure_concept_direct_suppressed` is `TRUE` -- the
#'   figure in those rows is the intergovernmental leg alone, not Direct +
#'   IG.
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
.abort_concept_not_aggregatable <- function(verb) {
  cli::cli_abort(c(
    "{.code expenditure_concept = \"total\"} cannot be used in {.fn {verb}}.",
    "*" = "Use {.code expenditure_concept = \"direct\"} (the default) for any \\
           comparison or sum that spans more than one government.",
    "i" = "Why: Census \"Total\" is a government's own Direct spending PLUS the \\
           money it hands to other governments. The receiving government reports \\
           that same dollar again as its own Direct when it actually spends it, \\
           so combining Total across governments double-counts intergovernmental \\
           transfers.",
    "i" = "For one government's own Total, use \\
           {.code cog_spending(expenditure_concept = \"total\")}."
  ), class = "uscogdata_concept_not_aggregatable")
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

  # .verb_spendrev() is shared with cog_revenue(), which never exposes
  # expenditure_concept and always resolves it to "direct" -- so nothing on
  # the public API can reach this today. But it's a cheap guard against a
  # future call (direct or via a modified cog_revenue()) that would UNION
  # the IG leg's expenditure M/L rows into a revenue result, which has no
  # matching IG view and no sensible meaning.
  if (identical(expenditure_concept, "total") &&
      !identical(view_base, "spending_annotated")) {
    cli::cli_abort(
      paste0(
        "`expenditure_concept = \"total\"` is only supported for spending ",
        "(view_base = \"spending_annotated\"); got view_base = ",
        "{.val {view_base}}."
      ),
      class = "uscogdata_expenditure_concept_unsupported"
    )
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
      .require_ig_categories(con)
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
    # C1(a): gap detection must run against the Direct leg alone. `result`
    # can also carry UNION'd intergovernmental rows (expenditure_concept =
    # "total"), and the wide era (<= FY2011) routinely has legacy IG dollars
    # surviving (ig_long deliberately keeps aggregate rows) for a
    # (year, category) whose legacy Direct dollars were suppressed (spending_
    # long/spending_long_harmonized both filter NOT is_aggregate). Passing
    # the UNION'd result here would let a surviving IG row count as coverage
    # and silently cancel the recipe-hint suggestion that should fire.
    direct_leg_result <- if (identical(expenditure_concept, "total")) {
      result[!(result[[subtype_col]] %in% "intergovernmental"), , drop = FALSE]
    } else {
      result
    }
    suggestions <- .build_suggestions(con, govid, years, category,
                                       direct_leg_result,
                                       resolved$basis, flow_prefixes)
  }

  # C1(b): when expenditure_concept = "total", flag any row where the IG
  # leg has dollars but the Direct leg has none for that same (year,
  # canonical_govid, category) -- the UNION'd figure there is
  # intergovernmental money ALONE, not Direct + IG, and both the row-level
  # notes and the provenance must say so rather than pass silently as a
  # plausible Total.
  direct_suppressed <- if (identical(expenditure_concept, "total")) {
    .detect_direct_suppressed(result, subtype_col)
  } else {
    rep(FALSE, nrow(result))
  }
  direct_suppressed_flag <- isTRUE(any(direct_suppressed))

  result$notes <- .notes_column(result, direct_suppressed, suggestions)

  # Determine expenditure_concept_note: only non-empty for "total", explains
  # how the IG leg was assembled from legacy-era aggregates. When the Direct
  # leg is suppressed for at least one requested (year, category), append an
  # explicit warning rather than let the base note's "Total = Direct + IG"
  # framing stand unqualified for rows where that arithmetic didn't happen.
  expenditure_concept_note_for_prov <- if (identical(expenditure_concept, "total")) {
    base_note <- "Total = Direct + intergovernmental (M to local govts + L to state govts). Legacy-era IG is assembled from aggregate-flagged rows, which are year-disjoint from their modern leaf components; the L-- family total is excluded."
    if (direct_suppressed_flag) {
      paste0(
        base_note,
        " NOTE: for at least one requested (year, category) the Direct leg ",
        "has NO rows in this corpus (a legacy aggregate-only family) -- the ",
        "affected result rows report the intergovernmental leg alone, not ",
        "Direct + IG. See `expenditure_concept_direct_suppressed` and each ",
        "affected row's `notes`."
      )
    } else {
      base_note
    }
  } else {
    NA_character_
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
    expenditure_concept = expenditure_concept,
    expenditure_concept_note = expenditure_concept_note_for_prov,
    expenditure_concept_direct_suppressed = direct_suppressed_flag,
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

#' Abort unless the active corpus's `summary_categories` actually carries
#' intergovernmental (M/L) rows.
#'
#' The 66 M/L category rows arrived via cog_pipeline PR #59 with NO
#' `schema_version` bump (`DESCRIPTION` still declares `MinCorpusSchema: 4`),
#' so `schema_version` alone cannot gate `expenditure_concept = "total"` --
#' a pre-#59 corpus can validly report schema_version 4, 5, or 6 and still
#' have zero M/L rows in `summary_categories`. Against such a corpus,
#' `ig_annotated`'s LEFT JOIN to `summary_categories` silently produces NA
#' `category`/`spend_subtype` for every IG row: with a `category` filter
#' this returns 0 rows (reads as "no intergovernmental spending" rather than
#' "can't tell"), and with `category = NULL` every IG dollar collapses into
#' one NA-subtype group that is invisible to the `spend_subtype ==
#' "intergovernmental"` filter this package's own tests, roxygen, and
#' vignette all rely on. Checking the data directly (rather than
#' schema_version) is the only reliable gate.
#' @noRd
.require_ig_categories <- function(con, what = "expenditure_concept = \"total\"") {
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM summary_categories WHERE LEFT(item_code, 1) IN ('M', 'L')"
  )$n
  if (identical(as.integer(n), 0L)) {
    cli::cli_abort(c(
      sprintf("%s requires a corpus with intergovernmental category rows.", what),
      x = "The active corpus's `summary_categories` has no M/L (intergovernmental) rows.",
      i = "This corpus predates the intergovernmental category rows added by cog_pipeline PR #59.",
      i = "Point USCOGDATA_URL at a newer corpus that includes the M/L summary_categories rows."
    ), class = "uscogdata_ig_categories_unsupported")
  }
  invisible(TRUE)
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

  # bool_or(), not bool_and(): a no-op for the Direct/revenue legs (those
  # views filter NOT is_aggregate, so no row in any group is ever aggregate),
  # but load-bearing for the IG leg, which deliberately keeps aggregate rows
  # (see inst/sql/24-ig_long.sql). The wide era is dense -- every government
  # has a row for every code in a family, most of them $0 -- so a $0 leaf
  # commonly lands in the same (year, gov, subtype, category) group as the
  # real aggregate row. bool_and() would then read FALSE for that group even
  # though its dollars came entirely from an aggregate row, silently
  # suppressing the "Aggregate fallback applied" note on exactly the rows
  # this feature exists to surface.
  sprintf(
    "SELECT
       year,
       canonical_govid,
       COALESCE(xwalk_gov_name, gov_name) AS gov_name,
       %1$s,
       category,
       SUM(amt) * 1000.0 AS amt_nominal,
       string_agg(DISTINCT item_code, ',' ORDER BY item_code) AS codes_included,
       bool_or(is_aggregate) AS aggregate_fallback
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

#' Detect rows where expenditure_concept = "total" is reporting the
#' intergovernmental leg with NO Direct counterpart in the same (year,
#' canonical_govid, category) group -- i.e. the Direct leg is suppressed
#' (typically a legacy aggregate-only family, see C1(a) above) rather than
#' genuinely zero. `TRUE` only for the `spend_subtype == "intergovernmental"`
#' row(s) in each such group.
#' @noRd
.detect_direct_suppressed <- function(result, subtype_col) {
  n <- nrow(result)
  if (n == 0L) return(logical(0))
  is_ig <- result[[subtype_col]] %in% "intergovernmental"
  if (!any(is_ig)) return(rep(FALSE, n))
  key <- paste(result$year, result$canonical_govid, result$category, sep = "\r")
  has_direct <- key %in% unique(key[!is_ig])
  is_ig & !has_direct
}

#' Build the notes text for a direct-suppressed row: names the recipe that
#' recovers the missing Direct component when one of the (already
#' Direct-leg-scoped, see C1(a)) suggestions covers this row's year, or a
#' generic fallback when no such recipe was found.
#' @noRd
.direct_suppressed_note <- function(year, suggestions) {
  matching <- Filter(function(s) {
    ay <- s$available_years
    !is.null(ay) && length(ay) == 2L && year >= ay[1] && year <= ay[2]
  }, suggestions)
  if (length(matching) == 0L) {
    return(paste(
      "Direct component is unavailable through this basis for this year",
      "(legacy aggregate-only family); no covering recipe found in this",
      "corpus -- see cog_recipes()."
    ))
  }
  ids <- sort(unique(vapply(matching, function(s) s$recipe_id, character(1))))
  sprintf(
    "Direct component is unavailable through this basis for this year; recover it via recipe = '%s' (see cog_recipes()).",
    paste(ids, collapse = "', '")
  )
}

#' @noRd
.notes_column <- function(result, direct_suppressed = NULL, suggestions = list()) {
  n <- nrow(result)
  if (n == 0L) return(character(0))
  parts <- vector("list", 3L)
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
  parts[[3]] <- if (!is.null(direct_suppressed) && any(direct_suppressed)) {
    vapply(seq_len(n), function(i) {
      if (!isTRUE(direct_suppressed[i])) return(NA_character_)
      .direct_suppressed_note(result$year[i], suggestions)
    }, character(1))
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
