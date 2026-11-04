# R/suggestions.R
# Recipe-component-driven signposting. When a basis = "harmonized" query for
# a category comes back incomplete in some requested year -- and a
# harmonization recipe would actually fill it for this government -- surface
# that recipe as a suggestion. "Incomplete" has two forms, and a recipe
# qualifies on either:
#   1. empty_year          -- the result has no rows at all in that year.
#   2. suppressed_component -- the result HAS rows, but a component code
#      carries dollars the verb's own long view structurally excludes
#      (aggregate-published, or absent from summary_categories). This is
#      uscogdata#9: Public Welfare kept returning E74/E79 rows while dropping
#      aggregate-only E67/E68, so form 1 never fired and the caller got a
#      number a third too low with no signpost at all.
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
#
# C1(a): for expenditure_concept = "total" callers, `result` here must
# already be the Direct-leg subset (the caller filters out
# spend_subtype == "intergovernmental" rows before calling in). A gap year
# is "the requested year has no Direct rows", never "no rows at all" --
# an IG row surviving on a legacy aggregate that Direct excludes must not
# read as coverage and cancel the very suggestion that would recover it.

#' Coverage suggestions for a spending or revenue query
#'
#' Builds the harmonization-recipe suggestions that [cog_spending()] and
#' [cog_revenue()] attach as `attr(x, "provenance")$suggestions`, without
#' running the verb again. Call a verb once with no `category`, filter its
#' rows yourself, and call this when you need the suggestions for one
#' category.
#'
#' A suggestion names a recipe (see [cog_recipes()]) that would fill a gap in
#' the result. A recipe qualifies in two ways. Its `trigger` is
#' `"empty_year"` when the result has no rows in a requested year and the
#' recipe's own join finds rows for these governments in that year. Its
#' `trigger` is `"suppressed_component"` when one of the recipe's component
#' codes carries dollars that the verb's own view excludes, because Census
#' published them only as an aggregate or because the code is absent from
#' `summary_categories`.
#'
#' Suggestions are built only for the verbs' default `basis = "harmonized"`.
#' On a corpus with `schema_version < 5` that basis is unavailable, the verbs
#' fall back to `"raw"`, and this function returns an empty list, as the
#' verbs do. It also returns an empty list when nothing qualifies.
#'
#' The verbs also print the suggestions as a message. This function returns
#' them without printing.
#'
#' @param govid Character vector of `canonical_govid` values, or a data frame
#'   with a `canonical_govid` column, such as a [cog_find_peers()] or
#'   [cog_gov_search()] result. The suggestions cover these governments as one
#'   cohort, as they do in a verb call over the same `govid`.
#' @param years Integer vector of requested years.
#' @param category Character vector of category names from
#'   `summary_categories.category`, or the reserved `"All Categories"` alone.
#'   The verbs build suggestions only when a category is named, so `NULL` is
#'   refused here.
#' @param flow `"spending"` for the suggestions [cog_spending()] would attach,
#'   or `"revenue"` for [cog_revenue()]'s.
#' @param concept The verb's concept argument: `expenditure_concept` for
#'   spending (`"primary"`, `"direct"` or `"total"`) or `revenue_concept` for
#'   revenue (`"general"` or `"total"`). `NULL`, the default, uses the verb's
#'   own default, `"primary"` or `"general"`. The concept changes the result
#'   only when `category = "All Categories"`, where its subtype scope decides
#'   which recipes are candidates.
#' @param years_present Integer vector of the years in which your rows for
#'   `category` have at least one row. Pass `integer(0)` when there are no
#'   rows. Years outside `years` are ignored. With `flow = "spending"` and
#'   `concept = "total"`, count only rows whose `spend_subtype` is not
#'   `"intergovernmental"`. [cog_spending()] measures gaps on the Direct leg
#'   alone, because an intergovernmental row can survive in a year whose
#'   Direct rows Census published only as an aggregate.
#' @return A list with one element per suggestion, ordered by `recipe_id`,
#'   and identical to `attr(x, "provenance")$suggestions` for the same
#'   inputs. Each element is a list with `recipe_id`, `label`,
#'   `available_years` (first and last year the recipe covers), `hint`,
#'   `trigger` (`"empty_year"` or `"suppressed_component"`),
#'   `suppressed_amount` (full US dollars), `suppressed_years`,
#'   `suppressed_codes`, and `ig_recipe_id` (the intergovernmental
#'   counterpart recipe, or `NULL`). The list is empty when nothing qualifies.
#' @seealso [cog_spending()], [cog_revenue()], [cog_recipes()],
#'   [cog_explain()]
#' @examples
#' \dontrun{
#' govids <- c("061037123085", "121011212191")
#' spend <- cog_spending(govids, years = 2011:2012)
#'
#' corrections <- spend[spend$category == "Corrections", ]
#' cog_suggestions(
#'   govids, years = 2011:2012, category = "Corrections",
#'   flow = "spending", years_present = unique(corrections$year)
#' )
#' }
#' @export
cog_suggestions <- function(govid, years, category,
                            flow = c("spending", "revenue"),
                            concept = NULL, years_present) {
  args <- .validate_suggestion_inputs(govid, years, category, flow, concept,
                                      years_present)

  con <- .ensure_session()
  # The verbs' default basis, resolved the way .verb_spendrev() resolves it
  # when the caller leaves `basis` unset: "raw" on a schema_version < 5
  # corpus, where .build_suggestions() returns list() before touching the
  # harmonization tables that corpus does not have.
  resolved <- .resolve_basis("harmonized", explicit = FALSE,
                             .uscogdata_env$manifest)

  .build_suggestions(
    con, .make_cohort(args$govid), args$years, args$category,
    data.frame(year = args$years_present), resolved$basis,
    args$spec$flow_prefixes,
    .select_long_view(args$spec$view_base, resolved$basis),
    all_categories = args$all_categories,
    subtype_col = args$spec$subtype_col,
    subtype_scope = args$subtype_scope
  )
}

# What cog_spending() and cog_revenue() pass to .verb_spendrev() for the
# arguments .build_suggestions() reads. tests/testthat/test-suggestions.R
# checks that cog_suggestions() returns what each verb attaches, so a change
# to either verb's flow family that is not mirrored here fails there.
.SUGGESTION_FLOWS <- list(
  spending = list(view_base     = "spending_annotated",
                  subtype_col   = "spend_subtype",
                  flow_prefixes = c("E", "F", "G"),
                  concepts      = c("primary", "direct", "total"),
                  concept_arg   = "expenditure_concept"),
  revenue  = list(view_base     = "revenue_annotated",
                  subtype_col   = "revenue_subtype",
                  flow_prefixes = c("T", "A", "U", "B", "C", "D"),
                  concepts      = c("general", "total"),
                  concept_arg   = "revenue_concept")
)

#' Validate and normalize `cog_suggestions()` arguments.
#'
#' Every check runs before `.ensure_session()`, so a malformed call costs no
#' I/O. Returns the coerced inputs plus the flow's spec from
#' `.SUGGESTION_FLOWS` and the concept's subtype scope.
#' @noRd
.validate_suggestion_inputs <- function(govid, years, category, flow,
                                        concept, years_present) {
  if (missing(govid)) cli::cli_abort("{.arg govid} is required.")
  if (missing(years)) cli::cli_abort("{.arg years} is required.")
  if (missing(category)) cli::cli_abort("{.arg category} is required.")
  if (missing(years_present)) {
    cli::cli_abort(c(
      "{.arg years_present} is required.",
      "i" = "Pass the years in which your rows for {.arg category} have at least one row, or {.code integer(0)} when there are none."
    ))
  }

  govid <- .coerce_govid_input(govid, arg = "govid")
  if (length(govid) == 0L || anyNA(govid) || !all(nzchar(govid))) {
    cli::cli_abort("{.arg govid} must name at least one government, with no missing or empty ids.")
  }

  if (!is.numeric(years) || length(years) == 0L || anyNA(years)) {
    cli::cli_abort("{.arg years} must be a non-empty integer vector with no missing values.")
  }

  if (is.null(category)) {
    cli::cli_abort(c(
      "{.arg category} must name at least one category.",
      "i" = "The verbs build suggestions only when a category is named, so a {.code NULL} category has none."
    ))
  }
  if (!is.character(category) || length(category) == 0L || anyNA(category)) {
    cli::cli_abort("{.arg category} must be a non-empty character vector with no missing values.")
  }
  all_categories <- .ALL_CATEGORIES %in% category
  if (all_categories && length(category) > 1L) {
    cli::cli_abort(c(
      "{.val {(.ALL_CATEGORIES)}} cannot be combined with other categories.",
      "i" = "It already covers every category in the requested concept's scope.",
      "*" = "Ask for it alone, or list the specific categories you want."
    ), class = "uscogdata_all_categories_not_combinable")
  }

  flow <- tryCatch(
    match.arg(flow, names(.SUGGESTION_FLOWS)),
    error = function(e) {
      cli::cli_abort(
        "{.arg flow} must be one of {.val spending} or {.val revenue}.",
        class = "uscogdata_invalid_flow", parent = e
      )
    }
  )
  spec <- .SUGGESTION_FLOWS[[flow]]

  if (is.null(concept)) concept <- spec$concepts[[1]]
  if (!is.character(concept) || length(concept) != 1L ||
      !concept %in% spec$concepts) {
    cli::cli_abort(
      "With {.code flow = \"{flow}\"}, {.arg concept} must be {.code NULL} or one of {.val {spec$concepts}}.",
      class = paste0("uscogdata_invalid_", spec$concept_arg)
    )
  }
  subtype_scope <- if (identical(flow, "spending")) {
    .expenditure_concept_subtypes(concept)
  } else {
    .revenue_concept_subtypes(concept)
  }

  if (!is.numeric(years_present) || anyNA(years_present)) {
    cli::cli_abort(c(
      "{.arg years_present} must be an integer vector with no missing values.",
      "i" = "Use {.code integer(0)} when your rows cover no years."
    ))
  }

  list(govid = govid, years = as.integer(years), category = category,
       all_categories = all_categories, spec = spec,
       subtype_scope = subtype_scope,
       years_present = as.integer(years_present))
}

#' Build the `prov$suggestions` list for a (non-recipe) basis = "harmonized"
#' verb call: recipes whose generic join would fill a real gap in `result`.
#'
#' @param con Active DuckDB connection.
#' @param cohort The verb's cohort object (see `.make_cohort()`), naming the
#'   governments by id, by state/type predicate, or both.
#' @param years Integer vector of requested years.
#' @param category `category` argument as passed to the verb (character
#'   vector or `NULL`; suggestions are only computed when non-NULL).
#' @param result The verb's already-computed result tibble (post basis
#'   query, pre per_capita/adjust_to_year), pre-filtered to the Direct leg
#'   only when the caller's `expenditure_concept = "total"` (see C1(a)).
#' @param basis The *resolved* basis (`"harmonized"` or `"raw"`).
#' @param flow_prefixes The calling verb's own flow-type prefixes (e.g.
#'   `c("E", "F", "G")` for `cog_spending()`, `c("T", "A", "U", "B", "C",
#'   "D")` for `cog_revenue()` -- see `.verb_spendrev()`). Passed through to
#'   `.attach_ig_counterparts()` to keep the intergovernmental-counterpart
#'   lookup scoped to the calling verb's own flow family.
#' @param long_view Name of the verb's own long view (from
#'   `.select_long_view()`), passed through to `.suppressed_components()` to
#'   measure the second qualifying path (uscogdata#9).
#' @param all_categories `TRUE` when the caller's `category` is the reserved
#'   pseudo-category (`.ALL_CATEGORIES`). Defaults to `FALSE` so no other
#'   caller's behaviour changes. When `TRUE`, the candidate-recipe sub-select
#'   is scoped by `subtype_col`/`subtype_scope` instead of by `category` --
#'   symmetric with `.build_verb_sql()`'s own all-categories branch (see
#'   R/spending.R): the concept's subtype allowlist is the real scope
#'   boundary, not any literal category value, and
#'   `.ALL_CATEGORIES` ("All Categories") is never itself a row in
#'   `summary_categories.category`, so leaving the category-keyed sub-select
#'   in place here always returned zero candidates and silently disabled
#'   signposting in all-categories mode (final whole-branch review, finding
#'   6).
#' @param subtype_col Name of the `summary_categories` subtype column to
#'   scope by when `all_categories = TRUE` (`"spend_subtype"` or
#'   `"revenue_subtype"` -- the same value `.build_verb_sql()` already
#'   receives as its own `subtype_col`). Ignored when `all_categories =
#'   FALSE`. `NULL` by default.
#' @param subtype_scope Character vector of subtype values to scope by when
#'   `all_categories = TRUE` (the same value `.build_verb_sql()` already
#'   receives as its own `subtype_scope` -- the concept's subtype allowlist,
#'   e.g. `.expenditure_concept_subtypes(expenditure_concept)`). Ignored when
#'   `all_categories = FALSE`. `NULL` by default.
#' @return List of `list(recipe_id, label, available_years, hint,
#'   ig_recipe_id, trigger, suppressed_amount, suppressed_years,
#'   suppressed_codes)`, possibly empty.
#'
#' Decomposed (Issue #33) into three extracted helpers to stay within the
#' project's "functions under 50 lines" convention:
#' \itemize{
#'   \item `.query_candidate_recipes()` -- candidate recipe lookup by
#'     category/subtype scope + `category_type` filter (#34) + M/L exclusion.
#'   \item `.query_recipe_meta()` -- metadata (label, year spans).
#'   \item `.query_covered_years()` -- Path 1 gap-year coverage via the
#'     recipe's own generic join.
#' }
#' The for-loop that merges covered-years + suppressed-components into
#' suggestion objects stays inline here because it interleaves
#' empty_hit/supp_hit precedence with field assembly. Likewise kept inline:
#' the M/L-exclusion design-comment block and the final
#' `.attach_ig_counterparts()` call.
#' @noRd
.build_suggestions <- function(con, cohort, years, category, result, basis,
                                flow_prefixes, long_view,
                                all_categories = FALSE,
                                subtype_col = NULL, subtype_scope = NULL) {
  if (!identical(basis, "harmonized") || is.null(category)) return(list())

  # Exclude any recipe that is ITSELF an intergovernmental (M/L) recipe --
  # i.e. every one of its own component codes is M/L-prefixed. Without this,
  # a category whose summary_categories rows span both a Direct family
  # (e.g. E04/E05, "Corrections") and its M/L counterpart (M04/M05, same
  # category since Task 1) makes the M/L recipe itself (e.g.
  # `corrections_ig_local_combined`) a raw top-level candidate for a plain
  # (Direct) cog_spending() call -- following that hint would silently
  # return intergovernmental dollars under `expenditure_concept = "direct"`
  # provenance. This is a stronger, unconditional exclusion than the
  # flow-prefix gate below/in `.attach_ig_counterparts()`: an M/L recipe
  # should never be suggested as a coverage-gap filler for EITHER verb, not
  # just kept from being named as the *counterpart* of another suggestion.
  #
  # The inner sub-select is the concept boundary (finding 6, final
  # whole-branch review): in all-categories mode it is scoped by
  # `subtype_col`/`subtype_scope` -- the same allowlist `.build_verb_sql()`
  # applies as a WHERE predicate to make the summed result a *concept*, not
  # by `category` (`.ALL_CATEGORIES` is never a row in
  # `summary_categories.category`, so a category-keyed sub-select always
  # came back empty here). The M/L exclusion below is unchanged either way.
  #
  # Issue #34: scope the candidate query by `category_type` ('expenditure'
  # vs 'revenue') to prevent cross-flow-family leakage -- e.g.
  # `cog_revenue(category = "Corrections")` must not surface
  # expenditure-only recipes (E04/E05) merely because they share the same
  # category name in summary_categories. The type is derived from
  # flow_prefixes: E/F/G -> 'expenditure', anything else -> 'revenue'.
  candidates <- .query_candidate_recipes(con, category, flow_prefixes,
                                          all_categories, subtype_col,
                                          subtype_scope)
  if (length(candidates) == 0L) return(list())

  result_years <- if (is.null(result) || nrow(result) == 0L) {
    integer(0)
  } else {
    unique(as.integer(result$year))
  }
  gap_years <- setdiff(as.integer(years), result_years)

  # Path 2 (uscogdata#9): component dollars this government holds that the
  # verb's own view structurally excludes. Measured across ALL requested
  # years, not just gap years -- the whole point is that a year with rows can
  # still be missing dollars. Scoped to the calling verb's own flow_prefixes
  # (I1) -- see `.suppressed_components()`'s own roxygen for why.
  #
  # This runs unconditionally whenever there are candidates -- an earlier
  # revision of this fix wave tried a free, in-memory pre-check
  # (`.needs_suppression_query()`) to skip the round trip on an already-
  # covered path, but a scoped re-review measured it against the fixture and
  # found it didn't pay for itself (it skipped ~3% of healthy calls, ~0% of
  # the multi-govid batch shape it was meant to help, at a net cost increase
  # once its own always-run metadata query was counted) while adding an
  # untested exactness invariant -- that `result$codes_included` and this
  # anti-join share the harmonized `item_code` space -- whose silent
  # violation would kill signposting, the exact failure class uscogdata#9
  # exists to prevent. Owner's call: keep this simple; a batch-aware
  # optimization, if one is worth building, is a separate issue.
  supp <- .suppressed_components(con, candidates, cohort, years, long_view, flow_prefixes)

  if (length(gap_years) == 0L && nrow(supp) == 0L) return(list())

  meta <- .query_recipe_meta(con, candidates)

  # Path 1 (unchanged): (recipe, year) pairs the recipe's own generic join
  # covers for this government, restricted to the gap years.
  covered <- .query_covered_years(con, candidates, cohort, gap_years)

  suggestions <- list()
  for (rid in candidates) {
    empty_hit <- rid %in% covered$recipe_id
    s_rows <- supp[supp$recipe_id == rid, , drop = FALSE]
    supp_hit <- nrow(s_rows) > 0L
    if (!empty_hit && !supp_hit) next
    m <- meta[meta$recipe_id == rid, ]
    suggestions[[length(suggestions) + 1L]] <- list(
      recipe_id = rid,
      label = m$label[[1]],
      available_years = c(as.integer(m$year_min), as.integer(m$year_max)),
      hint = sprintf("re-run with recipe = '%s'", rid),
      # An empty year is the stronger claim -- the category returned nothing
      # at all -- so it wins when both paths qualify. The suppressed_* fields
      # are still populated, so an empty_year fire also reports its dollars.
      trigger = if (empty_hit) "empty_year" else "suppressed_component",
      suppressed_amount = if (supp_hit) sum(s_rows$suppressed_amount) else 0,
      suppressed_years = if (supp_hit) {
        sort(unique(as.integer(s_rows$year)))
      } else {
        integer(0)
      },
      suppressed_codes = if (supp_hit) {
        sort(unique(unlist(strsplit(s_rows$suppressed_codes, ",", fixed = TRUE))))
      } else {
        character(0)
      }
    )
  }
  .attach_ig_counterparts(con, suggestions, flow_prefixes)
}

#' Query candidate harmonization recipe IDs for a coverage-gap suggestion.
#'
#' Selects recipes whose component codes fall within the requested scope
#' (category or subtype allowlist), excluding any recipe that is ITSELF an
#' intergovernmental (M/L) recipe -- i.e. every one of its own component
#' codes is M/L-prefixed. Without this exclusion, a category whose
#' summary_categories rows span both a Direct family (e.g. E04/E05,
#' "Corrections") and its M/L counterpart (M04/M05) makes the M/L recipe
#' itself a raw top-level candidate for a plain `cog_spending()` call --
#' following that hint would silently return intergovernmental dollars
#' under `expenditure_concept = "direct"` provenance.
#'
#' In all-categories mode (`all_categories = TRUE`) the inner sub-select is
#' scoped by `subtype_col`/`subtype_scope` -- the same allowlist
#' `.build_verb_sql()` applies as a WHERE predicate to make the summed
#' result a *concept* (see R/spending.R), not by `category`.
#' `.ALL_CATEGORIES` ("All Categories") is never itself a row in
#' `summary_categories.category`, so a category-keyed sub-select always
#' returns zero candidates and silently disables signposting.
#'
#' Scope is also by `category_type` ('expenditure' vs 'revenue', Issue #34)
#' to prevent cross-flow-family leakage: `cog_revenue(category =
#' "Corrections")` must not surface expenditure-only recipes (E04/E05)
#' merely because they share the same category name in summary_categories.
#' The type is derived from flow_prefixes: E/F/G -> 'expenditure', anything
#' else -> 'revenue'.
#'
#' @param con Active DuckDB connection.
#' @param category Category name, or `NULL`.
#' @param flow_prefixes The calling verb's own flow-type prefixes (see
#'   `.build_suggestions()`). Used to derive `category_type` (#34).
#' @param all_categories `TRUE` when the caller used `.ALL_CATEGORIES`.
#' @param subtype_col Name of the summary_categories subtype column to
#'   scope by when `all_categories = TRUE`; ignored otherwise.
#' @param subtype_scope Character vector of subtype values to scope by
#'   when `all_categories = TRUE`; ignored otherwise.
#' @return Character vector of recipe IDs (possibly empty), sorted by
#'   `recipe_id`. `.build_suggestions()` emits suggestions in this order, so
#'   the sort is what makes two identical calls return the same list in the
#'   same order (uscogdata#75). Without the `ORDER BY`, DuckDB returns
#'   `SELECT DISTINCT` rows in whatever order its parallel hash aggregate
#'   finishes in.
#' @noRd
.query_candidate_recipes <- function(con, category, flow_prefixes,
                                      all_categories = FALSE,
                                      subtype_col = NULL,
                                      subtype_scope = NULL) {
  # Issue #34: derive category_type from flow_prefixes to prevent
  # cross-flow-family leakage -- e.g. cog_revenue(category = "Corrections")
  # must not surface expenditure-only recipes merely because they share the
  # same category name in summary_categories.
  category_type <- if (all(flow_prefixes %in% c("E", "F", "G"))) {
    "expenditure"
  } else {
    "revenue"
  }

  candidate_scope_sql <- if (isTRUE(all_categories)) {
    sprintf(
      "SELECT DISTINCT item_code FROM summary_categories
       WHERE %s IN (%s) AND category_type = '%s'",
      subtype_col, .sql_lit_chr(subtype_scope), category_type
    )
  } else {
    sprintf(
      "SELECT DISTINCT item_code FROM summary_categories
       WHERE category IN (%s) AND category_type = '%s'",
      .sql_lit_chr(category), category_type
    )
  }

  DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT recipe_id FROM harmonization_recipes
     WHERE component_code IN (
       %s
     )
     AND recipe_id NOT IN (
       SELECT DISTINCT recipe_id FROM harmonization_recipes
       WHERE LEFT(component_code, 1) IN ('M', 'L')
     )
     ORDER BY recipe_id",
    candidate_scope_sql
  ))$recipe_id
}

#' Query gap-year coverage: which (recipe, year) pairs the recipe's own
#' generic join covers for this government, restricted to `gap_years`.
#'
#' This is Path 1 of a suggestion (unchanged): it finds recipes whose
#' component codes' generic join produces at least one row for this
#' government in each gap year -- i.e. the category returned nothing in
#' that year but a recipe would fill it.
#'
#' @param con Active DuckDB connection.
#' @param candidates Character vector of recipe IDs to check coverage for.
#' @param cohort The verb's cohort object (see `.make_cohort()`), rendered
#'   into the govid predicate on the joined `long` scan via `.cohort_sql()`.
#' @param gap_years Integer vector of requested years absent from the
#'   result.
#' @return Data frame with columns `recipe_id` (character) and `year`
#'   (integer). Returns an empty data frame (`recipe_id = character(0)`,
#'   `year = integer(0)`) when `gap_years` or `candidates` is empty, so
#'   callers can safely reference `$recipe_id`.
#' @noRd
.query_covered_years <- function(con, candidates, cohort, gap_years) {
  if (length(gap_years) == 0L || length(candidates) == 0L) {
    return(data.frame(recipe_id = character(0), year = integer(0)))
  }
  res <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT r.recipe_id, l.year
     FROM long l
     JOIN harmonization_recipes r
       ON l.item_code = r.component_code
      AND l.year BETWEEN r.year_min AND r.year_max
      AND (r.gov_type_scope = 'all'
           OR (r.gov_type_scope = 'state' AND l.type = 0)
           OR (r.gov_type_scope = 'local' AND l.type BETWEEN 1 AND 3))
     WHERE r.recipe_id IN (%s)
       AND %s
       AND l.year IN (%s)",
    .sql_lit_chr(candidates), .cohort_sql(cohort, "l.canonical_govid"),
    paste(gap_years, collapse = ",")
  ))
  res$year <- as.integer(res$year)
  res
}

#' Query recipe metadata: labels and year spans for a set of candidate
#' recipes.
#'
#' @param con Active DuckDB connection.
#' @param candidates Character vector of recipe IDs to look up.
#' @return Tibble with columns `recipe_id`, `label`, `year_min` (int), and
#'   `year_max` (int).
#' @noRd
.query_recipe_meta <- function(con, candidates) {
  tibble::as_tibble(DBI::dbGetQuery(con, sprintf(
    "SELECT recipe_id, any_value(label) AS label,
            MIN(year_min) AS year_min, MAX(year_max) AS year_max
     FROM harmonization_recipes
     WHERE recipe_id IN (%s)
     GROUP BY recipe_id",
    .sql_lit_chr(candidates)
  )))
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
#' `ige_local_m89_wide`'s {"89", "91", "92", "93"} on the shared "89" alone.
#' Checked by hand against the full harmonization_recipes catalog: only the
#' corrections family (E/F/G/M, suffixes 04/05) has an exact-set match in
#' this corpus.
#'
#' Exact-set suffix matching is NOT enough on its own, though: the same
#' reused-digit problem exists ACROSS the revenue-side IG families too.
#' `ig_local_d47_wide` (D47/D94, suffixes {"47","94"}) is an exact-set match
#' for `ige_local_m47_wide` (M47/M94, same suffixes) even though one is
#' intergovernmental REVENUE received from local governments and the other is
#' intergovernmental EXPENDITURE paid to local governments -- unrelated flows
#' that happen to reuse "47"/"94" for their own "transit/utilities" and
#' "other/combined" catch-alls. `ig_federal_b47_wide`, `ig_state_c47_wide`,
#' and their `*_89` siblings all collide the same way. None of this is
#' reachable via `cog_revenue()` in the bundled fixture today (its B/C/D
#' recipes never happen to have a covered gap year for any fixture govid),
#' but it IS reachable via a mis-scoped `cog_spending()` call on a
#' revenue-only category, e.g. `cog_spending(gov, category = "IG Federal")`
#' fires `ig_federal_b47_wide`/`ig_federal_b89_wide` for real in the fixture
#' -- so this is a live, not merely theoretical, gap.
#'
#' Two flow-family checks close this, both required (see
#' `tests/testthat/test-expenditure-concept.R`, "revenue-flavored ... never
#' receives an M/L counterpart" tests, for the pairwise verification):
#'   1. `own_prefix %in% flow_prefixes`: the firing recipe's own component
#'      codes must belong to the calling verb's own flow family (the same
#'      `flow_prefixes` `.build_harmonization_block()` uses, see
#'      `R/basis.R`). This blocks a recipe surfaced through a mis-scoped
#'      category from ever reaching the M/L search, e.g. `cog_spending()`'s
#'      flow_prefixes are `c("E","F","G")`, which `ig_federal_b47_wide`'s own
#'      `"B"` is not part of.
#'   2. `own_prefix %in% c("E","F","G")`: M/L only ever pairs with the
#'      DIRECT-expenditure family, never with revenue (`cog_revenue()`'s
#'      flow_prefixes already fold B/C/D in as ordinary revenue -- there is
#'      no separate "Total" bolt-on for revenue the way `expenditure_concept`
#'      adds one for spending) and never with ANOTHER M/L recipe (without
#'      this check, `ige_local_m47_wide` would wrongly match sibling
#'      `ige_state_l47_wide` on their shared {"47","94"} suffix set).
#'      Condition 1 alone does not catch this: under `cog_revenue()`,
#'      `ig_federal_b47_wide`'s own `"B"` IS inside revenue's own
#'      `flow_prefixes`, so only this second, family-specific check blocks
#'      the search.
#' @noRd
.attach_ig_counterparts <- function(con, suggestions, flow_prefixes) {
  if (length(suggestions) == 0L) return(suggestions)

  comp <- DBI::dbGetQuery(con,
    "SELECT recipe_id, component_code FROM harmonization_recipes")
  comp$prefix <- substr(comp$component_code, 1L, 1L)
  comp$suffix <- substr(comp$component_code, 2L, nchar(comp$component_code))
  suffix_sets <- lapply(split(comp$suffix, comp$recipe_id), function(x) sort(unique(x)))
  prefix_sets <- lapply(split(comp$prefix, comp$recipe_id), function(x) sort(unique(x)))

  ig_recipe_ids <- unique(comp$recipe_id[comp$prefix %in% c("M", "L")])

  find_counterpart <- function(rid) {
    own_prefix <- prefix_sets[[rid]]
    own_suffix <- suffix_sets[[rid]]
    if (is.null(own_prefix) || is.null(own_suffix)) return(NULL)
    if (!all(own_prefix %in% flow_prefixes)) return(NULL)
    if (!all(own_prefix %in% c("E", "F", "G"))) return(NULL)
    for (cand in ig_recipe_ids) {
      if (identical(cand, rid)) next
      if (setequal(suffix_sets[[cand]], own_suffix)) return(cand)
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
#' same bullet under cli, not a new bullet). Same treatment for
#' `suppressed_amount` (uscogdata#9): only present when dollars were
#' actually measured as excluded (an `empty_year` fire can carry them too --
#' see `.build_suggestions()` -- so this keys off the amount, not `trigger`).
#' @noRd
.inform_suggestions <- function(suggestions) {
  bullets <- vapply(suggestions, function(s) {
    bullet <- sprintf("%s (%d-%d): %s", s$recipe_id,
            s$available_years[1], s$available_years[2], s$hint)
    # Only present when dollars were actually measured as excluded. An
    # empty_year fire can carry them too -- the year had no rows AND the
    # component was suppressed -- which is strictly more informative.
    if (isTRUE(s$suppressed_amount > 0)) {
      bullet <- paste0(bullet, sprintf(
        "\n  $%s excluded from %s (%s), published as an aggregate or outside the crosswalk",
        formatC(s$suppressed_amount, format = "f", digits = 0, big.mark = ","),
        paste0("FY", s$suppressed_years, collapse = ", "),
        paste(s$suppressed_codes, collapse = ", ")))
    }
    if (!is.null(s$ig_recipe_id)) {
      bullet <- paste0(bullet, sprintf(
        "\n  intergovernmental counterpart: recipe = '%s'", s$ig_recipe_id))
    }
    bullet
  }, character(1))
  cli::cli_inform(c(
    i = "Incomplete coverage for the requested years; a harmonization recipe may fill it:",
    stats::setNames(bullets, rep("*", length(bullets)))
  ))
}
