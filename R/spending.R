# R/spending.R

# The three expenditure concepts (uscogdata#11), as sets of the crosswalk's
# `spend_subtype` values. Classification is crosswalk membership, never
# item-code first letters: prefix Y alone spans revenue (Y01/Y02),
# expenditure (Y05/Y06) and balance codes, so no first-letter allowlist can
# route it (finding F-018).
#
#   primary = operations + capital + assistance           (the default)
#   direct  = primary + interest + insurance_benefits     (Census Direct Expenditure)
#   total   = direct + intergovernmental                  (via the ig_* views)
#
# Census manual section 5.2.2.1: Direct Expenditure is ALL expenditure other
# than intergovernmental -- including payments to retirees, i.e. insurance
# trust benefits. Verified against Census's own published FY2020 state
# aggregates (20statetypepu.txt): `total` reproduces the published
# expenditure sum to the dollar; omitting insurance benefits understates
# California's Direct by 10.9%.
.spend_subtypes_primary <- c("operations", "capital", "assistance")
.spend_subtypes_direct  <- c(.spend_subtypes_primary, "interest", "insurance_benefits")

# The reserved pseudo-category. Deliberately NOT "Total": `category = "Total"`
# would sit one argument away from `expenditure_concept = "total"` and mean
# something different -- the concept selects WHICH SUBTYPES are in scope, this
# selects whether the rows inside that scope are broken out by category or
# summed. "All Categories" states the operation and cannot be misread as the
# concept.
.ALL_CATEGORIES <- "All Categories"

#' @noRd
.expenditure_concept_subtypes <- function(concept) {
  switch(concept,
    primary = .spend_subtypes_primary,
    # "total" = the direct subtypes here PLUS the intergovernmental leg,
    # which travels through the ig_* views rather than this scope (see
    # .build_verb_sql()).
    direct  = ,
    total   = .spend_subtypes_direct
  )
}

# The two revenue concepts (uscogdata#12), again as crosswalk subtype sets.
# Census's manual section 4.3 defines the first by SUBTRACTING from the second
# -- "General revenue comprises all revenue except that classified as liquor
# store, utility, or insurance trust revenue" -- giving the identity
#
#   Total Revenue = General + Utility + Liquor Store + Insurance Trust
#
# Verified against Census's own computed concept fields (IndFin FY2012,
# Wisconsin state): 31,410,686 + 0 + 0 + 4,469,906 = 35,880,592, exact.
.revenue_subtypes_general <- c("own_source", "federal", "state", "local_aid")
.revenue_subtypes_total   <- c(.revenue_subtypes_general, "utility",
                               "liquor_store", "insurance_trust")

#' @noRd
.revenue_concept_subtypes <- function(concept) {
  switch(concept,
    general = .revenue_subtypes_general,
    total   = .revenue_subtypes_total
  )
}

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
#'   `summary_categories.category`), or `NULL` for all categories broken out
#'   one row each. The reserved value `"All Categories"` instead returns a
#'   single summed row per `(year, canonical_govid, subtype)`, covering every
#'   category inside the requested concept's subtype scope. It cannot be
#'   combined with other category names, and it is not the same thing as
#'   `expenditure_concept = "total"`: the concept chooses which subtypes are in
#'   scope, `"All Categories"` chooses whether rows inside that scope are
#'   broken out or summed. Because the result keeps one row per
#'   `spend_subtype`, filtering the returned frame to
#'   `spend_subtype == "operations"` gives an operating-expenditure total.
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
#' @param expenditure_concept Which spending concept to return. Concepts are
#'   defined as sets of the crosswalk's `spend_subtype` values -- never as
#'   item-code first letters, which cannot classify correctly (prefix `Y`
#'   alone spans revenue, expenditure, and balance codes):
#'
#'   * `"primary"` (default) -- the government's own service provision:
#'     `operations` + `capital` + `assistance` subtypes.
#'   * `"direct"` -- Census's published Direct Expenditure: `primary` plus
#'     `interest` (interest on debt) and `insurance_benefits` (insurance
#'     trust benefit payments, e.g. pensions -- Census manual section
#'     5.2.2.1 includes payments to retirees in Direct).
#'   * `"total"` -- `direct` plus the intergovernmental leg: payments to
#'     local governments (`M` codes), to the state government (`L` codes,
#'     excluding the `L--` family-total rollup), and state payments to
#'     school systems (`Q11`/`Q12`/`Q18`), so results gain rows with
#'     `spend_subtype == "intergovernmental"`. Requires the active corpus's
#'     `summary_categories` to carry M/L rows (added by cog_pipeline PR
#'     #59); aborts with class `uscogdata_ig_categories_unsupported` on an
#'     older corpus rather than silently under-reporting. Mutually
#'     exclusive with `recipe` (a recipe already defines its own component
#'     codes).
#'
#'   **Do not sum `"total"` results across levels of government** (e.g.
#'   state + county + city): a state's `M12` payment to a school district is
#'   the same dollar the district reports as its own direct `E12`, so
#'   summing both double-counts it. This matters in particular with
#'   [cog_geographic_rollup()], which sums across exactly that kind of
#'   multi-layer government set.
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
#'   IG. When `category = "All Categories"` is combined with
#'   `expenditure_concept = "total"`, this detection cannot run (it keys on
#'   per-category rows, which all-categories mode collapses to one literal
#'   value), so `expenditure_concept_direct_suppressed` is `NA` rather than a
#'   possibly-false `FALSE`; query an explicit `category` to get a real
#'   answer.
#' @param complete If `TRUE`, fill the requested grid so that a cell the
#'   corpus does not carry still appears, labelled with **why** it is
#'   missing, and add a `value_source` column to every row:
#'
#'   * `"reported"` — the corpus carries this cell.
#'   * `"census_zero"` — dense-source year (`<= FY2011`), cell absent:
#'     Census published `$0`. `amt_nominal` is `0`.
#'   * `"not_reported"` — sparse-source year (`>= FY2012`), cell absent: the
#'     government did not report, and the value is unknown. `amt_nominal` is
#'     `NA`, **not** `0` — writing a zero there would invent data.
#'
#'   The grid comes from the corpus's `code_set` table, scoped to each
#'   government's own type, so a county is never filled with cells only a
#'   state can report. Reported rows are passed through untouched.
#'
#'   Defaults to `FALSE` (the historical behaviour: absent cells simply do
#'   not appear). Needs a corpus published from 2026-07-29 onward, which is
#'   when `representation`/`code_set` began shipping; aborts with class
#'   `uscogdata_representation_unavailable` otherwise. Not available with
#'   `recipe` or with `expenditure_concept = "total"` (class
#'   `uscogdata_complete_unsupported`) — neither draws its cells from
#'   `code_set`.
#' @return Tibble with columns `year`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real`,
#'   optional `amt_per_capita_nominal`, optional `amt_per_capita_real`,
#'   optional `pop_source`, `codes_included`, `aggregate_fallback`, `notes`,
#'   and `value_source` when `complete = TRUE`.
#'   Carries a `provenance` attribute matching `inst/schemas/provenance-v1.json`,
#'   whose `completion` block reports `applied`, `rows_filled`, and the
#'   per-year `absence_means` rule that was applied.
#' @export
cog_spending <- function(govid, years, category = NULL,
                         per_capita = FALSE, adjust_to_year = NULL,
                         basis = c("harmonized", "raw"), recipe = NULL,
                         expenditure_concept = c("primary", "direct", "total"),
                         complete = FALSE) {
  # flow_prefixes no longer classifies rows (crosswalk subtype membership
  # does, per expenditure_concept) -- it only scopes the recipe-suggestion
  # machinery to this verb's recipe families (see R/suggestions.R; the
  # catalog only has E/F/G-component direct-expenditure recipes).
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
    expenditure_concept = expenditure_concept,
    complete      = complete
  )
}

#' @noRd
.abort_concept_not_aggregatable <- function(verb) {
  cli::cli_abort(c(
    "{.code expenditure_concept = \"total\"} cannot be used in {.fn {verb}}.",
    "*" = "Use {.code expenditure_concept = \"primary\"} (the default) or \\
           {.code \"direct\"} for any comparison or sum that spans more than \\
           one government.",
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
                           expenditure_concept = c("primary", "direct", "total"),
                           revenue_concept = c("general", "total"),
                           complete = FALSE) {
  basis_explicit <- length(basis) == 1L
  basis <- match.arg(basis, c("harmonized", "raw"))
  # match.arg() itself throws a base `simpleError`, not an rlang-classed
  # condition; wrap it so an invalid expenditure_concept aborts consistently
  # with the rest of this package's validation (cli::cli_abort -> rlang_error).
  expenditure_concept <- tryCatch(
    match.arg(expenditure_concept, c("primary", "direct", "total")),
    error = function(e) {
      cli::cli_abort(
        "`expenditure_concept` must be one of {.val primary}, {.val direct}, or {.val total}.",
        class = "uscogdata_invalid_expenditure_concept",
        parent = e
      )
    }
  )

  revenue_concept <- tryCatch(
    match.arg(revenue_concept, c("general", "total")),
    error = function(e) {
      cli::cli_abort(
        "`revenue_concept` must be one of {.val general} or {.val total}.",
        class = "uscogdata_invalid_revenue_concept",
        parent = e
      )
    }
  )

  # The concept's subtype scope. Every code path below -- the verb SQL, the
  # harmonization exclusion count, and the complete = TRUE grid -- is scoped
  # by crosswalk subtype membership, never by item-code prefix. The
  # expenditure "total" concept's extra intergovernmental leg is the one
  # exception: it travels through the ig_* views rather than this scope,
  # because its legacy rows are aggregate-flagged.
  subtype_scope <- if (identical(subtype_col, "spend_subtype")) {
    .expenditure_concept_subtypes(expenditure_concept)
  } else {
    .revenue_concept_subtypes(revenue_concept)
  }

  govid <- .coerce_govid_input(govid, arg = "govid")
  # allow_all_categories = TRUE: cog_spending()/cog_revenue() are the two
  # verbs the reserved pseudo-category is defined for. cog_balances() shares
  # this validator but leaves the argument at its FALSE default, so it
  # rejects "All Categories" instead of silently returning zero rows
  # (finding 3, all-categories review).
  .validate_verb_inputs(govid, years, category, per_capita, adjust_to_year,
                        recipe, allow_all_categories = TRUE)

  # Recognize the reserved pseudo-category. Detected after type validation so a
  # non-character `category` still fails with the ordinary type error.
  all_categories <- !is.null(category) && .ALL_CATEGORIES %in% category
  if (all_categories && length(category) > 1L) {
    cli::cli_abort(c(
      "{.val {(.ALL_CATEGORIES)}} cannot be combined with other categories.",
      "i" = "It already sums every category in the requested concept's scope.",
      "*" = "Ask for it alone, or list the specific categories you want."
    ), class = "uscogdata_all_categories_not_combinable")
  }

  if (!is.null(recipe) && identical(expenditure_concept, "total")) {
    cli::cli_abort(c(
      "`recipe` and `expenditure_concept = \"total\"` are mutually exclusive.",
      i = "A recipe defines its own component codes; pass one or the other.",
      i = "For a recipe's intergovernmental counterpart, use the matching IG recipe (e.g. `corrections_ig_local_combined`)."
    ), class = "uscogdata_recipe_concept_conflict")
  }

  # .verb_spendrev() is shared with cog_revenue(), which never exposes
  # expenditure_concept and always resolves it to the default -- so nothing
  # on the public API can reach this today. But it's a cheap guard against a
  # future call (direct or via a modified cog_revenue()) that would UNION
  # the IG leg's expenditure M/L/Q rows into a revenue result, which has no
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

  complete <- isTRUE(complete)
  if (complete && !is.null(recipe)) {
    .abort_complete_unsupported(
      "A recipe defines its own component codes and never goes through `summary_categories`, so there is no grid to fill from.",
      "Query the recipe without `complete`, or use a category query with `complete = TRUE`."
    )
  }
  if (complete && identical(expenditure_concept, "total")) {
    .abort_complete_unsupported(
      "The intergovernmental leg deliberately keeps aggregate-flagged rows (see `inst/sql/24-ig_long.sql`), so its cells are not the ones `code_set` describes.",
      "Use `expenditure_concept = \"direct\"` with `complete = TRUE`, or drop `complete`."
    )
  }
  if (complete && all_categories) {
    .abort_complete_unsupported(
      "`category = \"All Categories\"` collapses the category dimension that `code_set` grids over (see `.completion_grid_sql()`), so there is no per-category grid left to fill -- filling a summed row has no defined semantics.",
      "Drop `complete`, or use `complete = TRUE` with an explicit `category` (or `category = NULL` for every category)."
    )
  }

  years   <- as.integer(years)
  if (!is.null(adjust_to_year)) adjust_to_year <- as.integer(adjust_to_year)

  con <- .ensure_session()
  manifest <- .uscogdata_env$manifest
  scope <- .check_govids_in_scope(govid)
  if (complete) .require_representation(con, manifest)

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
    sql <- .build_verb_sql(view, subtype_col, govid, years,
                           if (all_categories) NULL else category,
                           ig_view, subtype_scope,
                           all_categories = all_categories)
    result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  }

  # Fill BEFORE per_capita / inflation so the added cells get the same
  # treatment as reported ones: a census_zero stays $0 per capita and in real
  # dollars, and a not_reported stays NA through both rather than becoming a
  # spurious 0.
  completion <- list(applied = FALSE, rows_filled = 0L, absence_means = list())
  if (complete) {
    result <- .complete_result(result, con, subtype_col, govid, years,
                               category, subtype_scope)
    completion <- attr(result, ".completion")
    attr(result, ".completion") <- NULL
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
      con, govid, years, resolved, subtype_col, subtype_scope
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
                                       resolved$basis, flow_prefixes,
                                       .select_long_view(view_base, resolved$basis),
                                       all_categories = all_categories,
                                       subtype_col = subtype_col,
                                       subtype_scope = subtype_scope)
  }

  # C1(b): when expenditure_concept = "total", flag any row where the IG
  # leg has dollars but the Direct leg has none for that same (year,
  # canonical_govid, category) AND a harmonization recipe actually recovers
  # the missing Direct dollars for that exact triple -- see
  # .detect_direct_suppressed() for why bare Direct-row absence alone is NOT
  # sufficient (the dominant real cause is a government that simply has no
  # direct spending in that category, which is correct, ordinary data). When
  # a covering recipe is found, both the row-level notes and the provenance
  # say so rather than pass silently as a plausible Total.
  #
  # In all-categories mode this cannot run at all: .detect_direct_suppressed()
  # keys on (year, canonical_govid, category), and every row shares the same
  # literal "All Categories" value, so the key collides across every real
  # category for that (year, govid) -- an IG-only row for a suppressed
  # category becomes indistinguishable from one sharing a key with an
  # unrelated category's ordinary Direct row. `has_direct` would then read
  # TRUE whenever the government has ANY direct spending at all, and the
  # detector could never fire. Rather than run it and report a false FALSE,
  # skip it and record NA -- the provenance must stop making a claim it
  # cannot support (finding 1, all-categories review).
  suppression_unavailable <- all_categories &&
    identical(expenditure_concept, "total")
  direct_suppressed_info <- if (suppression_unavailable) {
    list(flag = rep(NA, nrow(result)), notes = rep(NA_character_, nrow(result)))
  } else if (identical(expenditure_concept, "total")) {
    .detect_direct_suppressed(con, result, subtype_col)
  } else {
    list(flag = rep(FALSE, nrow(result)), notes = rep(NA_character_, nrow(result)))
  }
  direct_suppressed <- direct_suppressed_info$flag
  direct_suppressed_flag <- if (suppression_unavailable) {
    NA
  } else {
    isTRUE(any(direct_suppressed))
  }

  result$notes <- .notes_column(result, direct_suppressed_info$notes)

  # Determine expenditure_concept_note: only non-empty for "total", explains
  # how the IG leg was assembled from legacy-era aggregates. When the Direct
  # leg is suppressed for at least one requested (year, category), append an
  # explicit warning rather than let the base note's "Total = Direct + IG"
  # framing stand unqualified for rows where that arithmetic didn't happen.
  # When suppression detection itself is unavailable (all-categories mode),
  # say so instead of silently reusing the unqualified base note.
  expenditure_concept_note_for_prov <- if (identical(expenditure_concept, "total")) {
    base_note <- "Total = Direct + intergovernmental (M to local govts + L to state govts). Legacy-era IG is assembled from aggregate-flagged rows, which are year-disjoint from their modern leaf components; the L-- family total is excluded."
    if (suppression_unavailable) {
      paste0(
        base_note,
        " NOTE: direct-leg-suppression detection is unavailable when ",
        "`category = \"All Categories\"` -- it keys on per-category rows, ",
        "which this mode collapses. `expenditure_concept_direct_suppressed` ",
        "is NA here rather than a possibly-false FALSE; query an explicit ",
        "`category` (or `category = NULL`) to get a real answer."
      )
    } else if (isTRUE(direct_suppressed_flag)) {
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
    revenue_concept = revenue_concept,
    harmonization  = harmonization,
    recipe         = recipe_block,
    suggestions    = suggestions,
    completion     = completion
  )
  prov$scope$govids_found   <- scope$found
  prov$scope$govids_missing <- scope$missing
  attr(result, "provenance") <- prov
  attr(result, ".popyear_range") <- NULL

  if (length(suggestions) > 0L) .inform_suggestions(suggestions)

  result
}

#' Shared input validation for the money/holdings verbs.
#'
#' `allow_all_categories` gates the reserved pseudo-category
#' `.ALL_CATEGORIES` ("All Categories"). It is meaningful only where a
#' concept's subtype scope defines what "all" sums over --
#' `cog_spending()`/`cog_revenue()`, via `.verb_spendrev()`, pass `TRUE`.
#' `cog_balances()` leaves it at the `FALSE` default: holdings are a stock
#' with no concept vocabulary to sum across (see R/balances.R), and before
#' this guard existed `cog_balances(category = "All Categories")` silently
#' matched zero crosswalk rows and returned an empty result with no error
#' (finding 3, all-categories review). This validator is shared specifically
#' so the three verbs cannot drift apart on this again.
#' @noRd
.validate_verb_inputs <- function(govid, years, category,
                                  per_capita, adjust_to_year, recipe = NULL,
                                  allow_all_categories = FALSE) {
  if (!is.character(govid) || length(govid) == 0L) {
    cli::cli_abort("`govid` must be a non-empty character vector.")
  }
  if (!(is.integer(years) || is.numeric(years)) || length(years) == 0L) {
    cli::cli_abort("`years` must be a non-empty integer vector.")
  }
  if (!is.null(category) && !is.character(category)) {
    cli::cli_abort("`category` must be character or NULL.")
  }
  if (!allow_all_categories && !is.null(category) &&
      .ALL_CATEGORIES %in% category) {
    cli::cli_abort(c(
      "{.val {(.ALL_CATEGORIES)}} is not supported here.",
      i = "It sums a spending or revenue concept's subtype scope; this verb has no concept vocabulary to sum across.",
      i = "Use {.fn cog_spending} or {.fn cog_revenue} for an all-categories total."
    ), class = "uscogdata_all_categories_unsupported")
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

#' The `*_long`/`*_long_harmonized` view behind an annotated view base --
#' `"spending_annotated"` -> `"spending_long_harmonized"`. `.build_suggestions()`
#' anti-joins the LONG view rather than the annotated one: they have identical
#' row membership (the annotated views are the long views plus LEFT JOINs, see
#' inst/sql/42-spending_annotated_harmonized.sql), but the long view is the
#' one that actually owns the `NOT is_aggregate` + crosswalk-membership rule
#' the suppression test is asking about.
#' @noRd
.select_long_view <- function(view_base, basis) {
  .select_view(sub("_annotated$", "_long", view_base), basis)
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
                            ig_view = NULL, subtype_scope = NULL,
                            all_categories = FALSE) {
  govid_lit <- .sql_lit_chr(govid)
  years_lit <- paste(as.integer(years), collapse = ",")
  # In all-categories mode there is no category filter: the sum is defined by
  # the concept's SUBTYPE allowlist (subtype_pred below), which is the real
  # concept boundary. Filtering by category as well would be a no-op at best
  # and, if the crosswalk ever gained an uncategorized code, a silent
  # under-count of the very total this mode exists to guarantee.
  category_pred <- if (all_categories || is.null(category)) {
    ""
  } else {
    sprintf("AND category IN (%s)", .sql_lit_chr(category))
  }

  # The concept's subtype allowlist (see .expenditure_concept_subtypes()).
  # The base views carry every subtype of their flow (spending_annotated has
  # all five non-IG expenditure subtypes); the concept narrows here. For
  # "total", the IG leg's rows are 'intergovernmental', so that value joins
  # the allowlist exactly when ig_view is present.
  subtype_pred <- if (is.null(subtype_scope)) {
    ""
  } else {
    scope <- if (is.null(ig_view)) subtype_scope else c(subtype_scope, "intergovernmental")
    sprintf("AND %s IN (%s)", subtype_col, .sql_lit_chr(scope))
  }

  # expenditure_concept = "total" adds the intergovernmental leg. UNION ALL,
  # never UNION: the two legs are disjoint by crosswalk subtype (the direct
  # view excludes 'intergovernmental'; the IG view is only that), so
  # de-duplication would be pure cost, and a silent row-drop if two
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

  # Collapse the category dimension. subtype is deliberately KEPT: it is what
  # lets a caller filter the result to `spend_subtype == "operations"` and
  # get an operating-expenditure total, the measure a fiscal comparison
  # actually wants. (There is no `subtype` argument -- this is a post-hoc
  # filter on the returned column, not a query parameter.)
  category_select <- if (all_categories) {
    sprintf("%s AS category", .sql_lit_chr(.ALL_CATEGORIES))
  } else {
    "category"
  }
  category_group <- if (all_categories) "" else ", category"

  sprintf(
    "SELECT
       year,
       canonical_govid,
       COALESCE(xwalk_gov_name, gov_name) AS gov_name,
       %1$s,
       %7$s,
       SUM(amt) * 1000.0 AS amt_nominal,
       string_agg(DISTINCT item_code, ',' ORDER BY item_code) AS codes_included,
       bool_or(is_aggregate) AS aggregate_fallback
     FROM %2$s
     WHERE canonical_govid IN (%3$s)
       AND year IN (%4$s)
       %5$s
       %6$s
     GROUP BY year, canonical_govid, gov_name, xwalk_gov_name, %1$s%8$s
     ORDER BY year, canonical_govid, %1$s%8$s",
    subtype_col, source_expr, govid_lit, years_lit, category_pred, subtype_pred,
    category_select, category_group
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
#' canonical_govid, category) group AND a harmonization recipe actually
#' recovers the missing Direct dollars for that exact (year, canonical_govid,
#' category) triple.
#'
#' Bare Direct-row absence is deliberately NOT sufficient on its own: the
#' dominant real cause of "no Direct sibling row" is a government that simply
#' has no direct spending in that category (e.g. a state that funds K-12
#' entirely through school districts), which is correct, ordinary data, not
#' suppression. Genuine suppression -- a legacy aggregate-only family whose
#' Direct-leg basis query excludes it by construction (spending_long/
#' spending_long_harmonized both filter NOT is_aggregate) -- always has a
#' covering harmonization recipe, because that is exactly what the recipe
#' catalog exists to recover (see R/suggestions.R and `cog_recipes()`). So
#' checking "does a recipe actually cover this triple" cleanly separates the
#' two cases instead of conflating them.
#'
#' Returns `list(flag, notes)`, both the same length as `result`: `flag` is
#' `TRUE` only for the `spend_subtype == "intergovernmental"` row(s) in a
#' suppressed group, and `notes` names the recovering recipe(s) for those
#' rows (`NA` everywhere else).
#' @noRd
.detect_direct_suppressed <- function(con, result, subtype_col) {
  n <- nrow(result)
  empty_notes <- rep(NA_character_, n)
  if (n == 0L) return(list(flag = logical(0), notes = character(0)))
  is_ig <- result[[subtype_col]] %in% "intergovernmental"
  if (!any(is_ig)) return(list(flag = rep(FALSE, n), notes = empty_notes))

  key <- paste(result$year, result$canonical_govid, result$category, sep = "\r")
  has_direct <- key %in% unique(key[!is_ig])
  candidate <- is_ig & !has_direct

  flag <- rep(FALSE, n)
  notes <- empty_notes
  if (!any(candidate)) return(list(flag = flag, notes = notes))

  idx <- which(candidate)
  rows <- unique(result[idx, c("year", "canonical_govid", "category")])
  covering <- .covering_recipes(con, rows)
  cov_key <- paste(covering$year, covering$canonical_govid, covering$category,
                    sep = "\r")

  for (i in idx) {
    k <- paste(result$year[i], result$canonical_govid[i], result$category[i],
               sep = "\r")
    m <- match(k, cov_key)
    if (is.na(m)) next
    ids <- covering$recipe_ids[[m]]
    if (length(ids) == 0L) next
    flag[i] <- TRUE
    notes[i] <- sprintf(
      "Direct component is unavailable through this basis for this year; recover it via recipe = '%s' (see cog_recipes()).",
      paste(sort(unique(ids)), collapse = "', '")
    )
  }
  list(flag = flag, notes = notes)
}

#' For each (year, canonical_govid, category) triple potentially affected by
#' a suppressed Direct leg, find the harmonization recipe(s) that (a) cover
#' this `category` (share a component item_code via `summary_categories`,
#' excluding any recipe that is itself entirely intergovernmental M/L -- the
#' same exclusion `.build_suggestions()` applies, see I2) and (b) actually
#' produce a `long` row for this exact (canonical_govid, year) via the same
#' generic join `.run_recipe()` uses (component year_min/year_max +
#' gov_type_scope, no is_aggregate filter -- a recipe's whole point is to
#' recover data that's aggregate-only). Adds a list-column `recipe_ids`
#' (possibly length-0) to `rows`.
#' @noRd
.covering_recipes <- function(con, rows) {
  rows$recipe_ids <- vector("list", nrow(rows))
  cats <- unique(rows$category[!is.na(rows$category)])
  if (length(cats) == 0L) return(rows)

  cand <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT sc.category, r.recipe_id
     FROM harmonization_recipes r
     JOIN summary_categories sc ON sc.item_code = r.component_code
     WHERE sc.category IN (%s)
       AND r.recipe_id NOT IN (
         SELECT DISTINCT recipe_id FROM harmonization_recipes
         WHERE LEFT(component_code, 1) IN ('M', 'L')
       )",
    .sql_lit_chr(cats)
  ))
  if (nrow(cand) == 0L) return(rows)

  recipe_ids_all <- unique(cand$recipe_id)
  govids <- unique(rows$canonical_govid)
  years  <- unique(rows$year)
  covered <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT r.recipe_id, l.canonical_govid, l.year
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
    .sql_lit_chr(recipe_ids_all), .sql_lit_chr(govids), paste(years, collapse = ",")
  ))

  for (i in seq_len(nrow(rows))) {
    cat_i <- rows$category[i]
    if (is.na(cat_i)) next
    cat_recipe_ids <- cand$recipe_id[cand$category == cat_i]
    if (length(cat_recipe_ids) == 0L) next
    sub <- covered[covered$canonical_govid == rows$canonical_govid[i] &
                   covered$year == rows$year[i] &
                   covered$recipe_id %in% cat_recipe_ids, ]
    rows$recipe_ids[[i]] <- sort(unique(sub$recipe_id))
  }
  rows
}

#' @noRd
.notes_column <- function(result, direct_suppressed_notes = NULL) {
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
  parts[[3]] <- if (!is.null(direct_suppressed_notes)) {
    direct_suppressed_notes
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
