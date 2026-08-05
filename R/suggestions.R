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
#' @return List of `list(recipe_id, label, available_years, hint,
#'   ig_recipe_id, trigger, suppressed_amount, suppressed_years,
#'   suppressed_codes)`, possibly empty.
#' @noRd
.build_suggestions <- function(con, govid, years, category, result, basis,
                                flow_prefixes, long_view) {
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
  candidates <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT recipe_id FROM harmonization_recipes
     WHERE component_code IN (
       SELECT DISTINCT item_code FROM summary_categories WHERE category IN (%s)
     )
     AND recipe_id NOT IN (
       SELECT DISTINCT recipe_id FROM harmonization_recipes
       WHERE LEFT(component_code, 1) IN ('M', 'L')
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
  supp <- .suppressed_components(con, candidates, govid, years, long_view, flow_prefixes)

  if (length(gap_years) == 0L && nrow(supp) == 0L) return(list())

  meta <- tibble::as_tibble(DBI::dbGetQuery(con, sprintf(
    "SELECT recipe_id, any_value(label) AS label,
            MIN(year_min) AS year_min, MAX(year_max) AS year_max
     FROM harmonization_recipes
     WHERE recipe_id IN (%s)
     GROUP BY recipe_id",
    .sql_lit_chr(candidates)
  )))

  # Path 1 (unchanged): (recipe, year) pairs the recipe's own generic join
  # covers for this government, restricted to the gap years.
  covered <- if (length(gap_years) == 0L) {
    data.frame(recipe_id = character(0), year = integer(0))
  } else {
    DBI::dbGetQuery(con, sprintf(
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
  }

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
