# Partial-Coverage Signposting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fire a harmonization-recipe suggestion when a requested category still returns rows but structurally excludes component dollars the corpus does hold — closing uscogdata#9, where `cog_spending(category = "Public Welfare")` silently drops aggregate-published `E67`/`E68` in legacy years.

**Architecture:** `.build_suggestions()` keeps its recipe-candidate query, M/L exclusion, and IG-counterpart attachment untouched. Its sole year test — "the result has zero rows in this year" — gains a parallel qualifying path: "a component code carries nonzero dollars for this government in this year that the verb's own long view structurally excludes." Reachability is decided by anti-joining the real view (`spending_long_harmonized` / `revenue_long_harmonized`) rather than restating its `WHERE` clause, so the trigger tracks the view if it changes. Both verbs inherit the fix from the shared `.verb_spendrev()` call site.

**Tech Stack:** R (pkg `uscogdata`), DuckDB via DBI, testthat 3e, cli. Downstream: cog-api (plumber).

## Global Constraints

- **No new package dependencies.** `withr` stays Suggests-only, test-only.
- **All tests run offline against the bundled fixture** at `inst/extdata/fixture_corpus/` (years 2011, 2012, 2019, 2020). No live corpus, no credentials. Guard every corpus-touching test with `skip_if_no_corpus()`.
- **Every dollar figure in this plan is measured**, not estimated — reproduced against the bundled fixture on 2026-08-04. Assert them exactly.
- **Raw `amt` is in $1,000s**; multiply by `1000.0` in SQL. Values reaching provenance are full US dollars.
- **Suggestions only run under `basis = "harmonized"` and a non-NULL `category`** — the early return at `R/suggestions.R:56` is unchanged and must stay.
- Functions under 50 lines, files under 400 lines. `R/suggestions.R` is currently 251 lines and must stay under 400.
- Use `.sql_lit_chr()` for every string literal interpolated into SQL. Never interpolate a user-supplied value as a SQL *identifier*.
- Commit after each task. Conventional-commit prefixes (`fix:`, `test:`, `docs:`, `chore:`).

## Reference Data (measured 2026-08-04, bundled fixture)

Government ids are `canonical_govid`.

| Case | gov | year | category | today | after |
|---|---|---|---|---|---|
| Target defect | `061037123085` (LA County) | 2011 | Public Welfare | `suggestions` = `list()`, reports $3,185,943,000 | 2 suggestions; `welfare_cash_e67_wide` $1,803,872,000 (E67), `welfare_cash_e68_wide` $271,589,000 (E68) |
| Revenue twin | `020000227749` (Alaska state) | 2011 | Miscellaneous Revenue | `suggestions` = `list()`, reports $943,842,000 from U11,U20,U30 | 1 suggestion; `rents_royalties_u4_wide` $1,899,995,000 (`U4-`) |
| Regression | `061037123085` | 2011 | Corrections | 3 suggestions, `empty_year` | same 3, now carrying $1,371,460,000 (E05), $17,373,000 (F05), $884,000 (G05) |
| Negative | `061037123085` | 2019 | Public Welfare | `list()` | `list()` |
| Negative | `higher_ed_e18_wide`, `general_gov_e89_wide` | any | any | never fire | never fire (E18/E89 are leaf-and-classified in 2011) |

**Structural invariant the anti-join rests on:** no recipe component is ever renamed by harmonization. Measured: 0 rows in `long` where `item_code` is a recipe component and `harmonized_code IS NOT NULL AND harmonized_code <> item_code`. All 19 components that differ have `harmonized_code IS NULL`, and every one is `is_aggregate = TRUE`.

**Pre-verified safe** — these existing assertions do *not* regress (0 new fires each):
- `test-recipes.R:196` Broward 2019:2020 Corrections
- `test-expenditure-concept.R:293` AL state 2019 Police
- `test-recipes.R:82` Broward `recipe = "corrections_combined"` — safe by construction; the recipe branch sets `suggestions <- list()` at `R/spending.R:376` and never calls `.build_suggestions()`

## File Structure

- **Modify `R/suggestions.R`** — add `.suppressed_components()`; widen `.build_suggestions()`; extend `.inform_suggestions()`. Owns the whole trigger.
- **Modify `R/spending.R`** — add `.select_long_view()` beside `.select_view()` (~line 511); pass the long-view name at the `.build_suggestions()` call site (~line 396).
- **Modify `R/explain.R`** — render the new detail in the Suggestions section (~line 127).
- **Modify `inst/schemas/provenance-v1.json`** — document the four new per-suggestion fields.
- **Modify `tests/testthat/test-recipes.R`** — all new reader tests (this file already owns signposting tests).
- **Modify `NEWS.md`** — user-facing entry.
- **Modify (cog-api) `api/tests/testthat/test-handlers-governments.R`** — assert the fields survive the envelope.

---

### Task 0: Pre-flight — clean branch off `main`

**Files:** none (git only)

**Interfaces:**
- Consumes: nothing
- Produces: a clean `fix/partial-coverage-signposting-9` branch based on `origin/main`; a recorded baseline test count later tasks compare against

> The working tree is currently on `ci/apt-https` with two **uncommitted fixture modifications** (`inst/extdata/fixture_corpus/data/series_breaks.parquet`, `inst/extdata/fixture_corpus/manifest.json`). Do not carry them into this branch and do not discard them without checking with the user — they are unrelated to this work.

- [ ] **Step 1: Inspect the uncommitted fixture changes**

```bash
cd ~/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata
git status --short
git diff --stat
```

Expected: exactly the two fixture files listed above, modified.

- [ ] **Step 2: Stash them, and say so in the stash message**

```bash
git stash push -m "WIP fixture series_breaks/manifest, unrelated to #9" \
  inst/extdata/fixture_corpus/data/series_breaks.parquet \
  inst/extdata/fixture_corpus/manifest.json
git status --short
```

Expected: clean tree. Report the stash ref to the user so it is not lost.

- [ ] **Step 3: Branch off current `main`**

```bash
git fetch origin
git checkout -b fix/partial-coverage-signposting-9 origin/main
git log --oneline -1
```

- [ ] **Step 4: Record the baseline test count**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(reporter = "summary")' 2>&1 | tail -20
```

Expected: a green suite. **Write the exact PASS/FAIL/SKIP/WARN numbers into the task notes** — every later task compares against them. Do not proceed if the baseline is already red; report to the user instead.

---

### Task 1: `.suppressed_components()` + the structural guard

**Files:**
- Modify: `R/suggestions.R` (append after `.build_suggestions()`, before `.attach_ig_counterparts()`)
- Modify: `R/spending.R:511-513` (add `.select_long_view()` beside `.select_view()`)
- Test: `tests/testthat/test-recipes.R` (append at end)

**Interfaces:**
- Consumes: `.sql_lit_chr(x)` (existing, `R/config.R`); `.select_view(view_base, basis)` (existing, `R/spending.R:511`)
- Produces:
  - `.select_long_view(view_base, basis)` → character(1). `"spending_annotated"` + `"harmonized"` → `"spending_long_harmonized"`.
  - `.suppressed_components(con, candidates, govid, years, long_view)` → tibble with columns `recipe_id` (chr), `year` (dbl), `suppressed_amount` (dbl, full US dollars), `suppressed_codes` (chr, comma-joined sorted item codes). Zero rows when nothing is suppressed. Aborts on a `long_view` outside the allowlist.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-recipes.R`:

```r
# --- uscogdata#9: partial-coverage signposting ------------------------------

test_that("no recipe component is ever renamed by harmonization", {
  # The suppression trigger anti-joins the verb's long view on item_code.
  # That is only sound because harmonization never rewrites a recipe
  # component's code -- every component whose harmonized_code differs has
  # harmonized_code IS NULL (and is aggregate-flagged). If this ever fails,
  # .suppressed_components() would report reachable dollars as suppressed.
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS renamed FROM long
     WHERE item_code IN (SELECT DISTINCT component_code FROM harmonization_recipes)
       AND harmonized_code IS NOT NULL
       AND harmonized_code <> item_code")$renamed
  expect_equal(as.integer(n), 0L)
})

test_that(".select_long_view maps annotated view bases to their long views", {
  expect_equal(
    uscogdata:::.select_long_view("spending_annotated", "harmonized"),
    "spending_long_harmonized")
  expect_equal(
    uscogdata:::.select_long_view("revenue_annotated", "harmonized"),
    "revenue_long_harmonized")
  expect_equal(
    uscogdata:::.select_long_view("spending_annotated", "raw"),
    "spending_long")
})

test_that(".suppressed_components measures the E67/E68 dollars Public Welfare drops", {
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  s <- uscogdata:::.suppressed_components(
    con,
    candidates = c("welfare_cash_e67_wide", "welfare_cash_e68_wide"),
    govid = "061037123085", years = 2011L,
    long_view = "spending_long_harmonized")

  expect_s3_class(s, "tbl_df")
  expect_equal(nrow(s), 2L)
  s <- s[order(s$recipe_id), ]
  expect_equal(s$recipe_id, c("welfare_cash_e67_wide", "welfare_cash_e68_wide"))
  expect_equal(s$suppressed_amount, c(1803872000, 271589000))
  expect_equal(s$suppressed_codes, c("E67", "E68"))
})

test_that(".suppressed_components finds nothing in a modern year", {
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  s <- uscogdata:::.suppressed_components(
    con,
    candidates = c("welfare_cash_e67_wide", "welfare_cash_e68_wide"),
    govid = "061037123085", years = 2019L,
    long_view = "spending_long_harmonized")
  expect_equal(nrow(s), 0L)
})

test_that(".suppressed_components rejects a long_view outside the allowlist", {
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  expect_error(
    uscogdata:::.suppressed_components(
      con, candidates = "welfare_cash_e67_wide", govid = "061037123085",
      years = 2011L, long_view = "long; DROP TABLE x"),
    class = "uscogdata_internal_error")
})
```

- [ ] **Step 2: Run to verify they fail**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(filter = "recipes")' 2>&1 | tail -30
```

Expected: FAIL — `.select_long_view` and `.suppressed_components` are not found. The "no recipe component is ever renamed" test should already PASS (it asserts existing corpus structure).

- [ ] **Step 3: Add `.select_long_view()` to `R/spending.R`**

Insert immediately after `.select_view()` (currently ends at line 513):

```r
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
```

- [ ] **Step 4: Add `.suppressed_components()` to `R/suggestions.R`**

Insert after `.build_suggestions()` closes (currently line 132), before the `.attach_ig_counterparts()` roxygen block:

```r
#' Measure, per (recipe, year), the component dollars this government holds
#' that the calling verb's own long view structurally excludes.
#'
#' This is the second qualifying path for a suggestion (uscogdata#9). The
#' first -- row absence -- only fires when a category returns NOTHING in a
#' requested year, which is how Corrections behaves in the wide era. Public
#' Welfare is the failure mode it misses: E74/E75/E77/E79 still return rows,
#' so there is no absence to detect, while E67/E68 (aggregate-flagged 1967-
#' 2011, and absent from `summary_categories` entirely) are dropped. The
#' caller gets a plausible number a third too low, silently.
#'
#' "Structurally excluded" is decided by anti-joining the verb's REAL long
#' view rather than restating its WHERE clause, so this stays correct if
#' `spending_long_harmonized` / `revenue_long_harmonized` ever change. That
#' anti-join is keyed on `item_code`, which is sound only because
#' harmonization never renames a recipe component -- asserted by the "no
#' recipe component is ever renamed by harmonization" test in
#' tests/testthat/test-recipes.R.
#'
#' Note what this deliberately does NOT count as suppressed: a component
#' excluded from the RESULT for scoping reasons -- because it belongs to a
#' different `category`, or because `expenditure_concept` narrowed the
#' subtypes -- is still present in the view, so it never fires. Suggesting a
#' recipe is a coverage fix, not a category redefinition. Measured on the
#' bundled fixture, this keeps `higher_ed_e18_wide` and `general_gov_e89_wide`
#' silent (E18/E89 are leaf-and-classified even in the wide era) and confines
#' every fire to 2011.
#'
#' @param con Active DuckDB connection.
#' @param candidates Character vector of recipe ids to measure.
#' @param govid Character vector of canonical_govid values.
#' @param years Integer vector of requested years.
#' @param long_view Name of the verb's long view, from `.select_long_view()`.
#' @return Tibble of `recipe_id`, `year`, `suppressed_amount` (full US
#'   dollars), `suppressed_codes` (comma-joined, sorted). Zero rows when
#'   nothing is suppressed.
#' @noRd
.suppressed_components <- function(con, candidates, govid, years, long_view) {
  empty <- tibble::tibble(
    recipe_id = character(0), year = numeric(0),
    suppressed_amount = numeric(0), suppressed_codes = character(0)
  )
  if (length(candidates) == 0L) return(empty)

  # long_view is interpolated as a SQL IDENTIFIER, not a literal, so it can
  # never be quoted safely. It is always internally derived from a fixed
  # view_base, so an off-allowlist value is a programming error, not input.
  if (!long_view %in% c("spending_long", "spending_long_harmonized",
                        "revenue_long", "revenue_long_harmonized")) {
    cli::cli_abort(
      "Internal error: unexpected `long_view` {.val {long_view}}.",
      class = "uscogdata_internal_error"
    )
  }

  sql <- sprintf(
    "SELECT r.recipe_id,
            l.year,
            SUM(l.amt) * 1000.0 AS suppressed_amount,
            string_agg(DISTINCT l.item_code, ',' ORDER BY l.item_code)
              AS suppressed_codes
     FROM long l
     JOIN harmonization_recipes r
       ON l.item_code = r.component_code
      AND l.year BETWEEN r.year_min AND r.year_max
      AND (r.gov_type_scope = 'all'
           OR (r.gov_type_scope = 'state' AND l.type = 0)
           OR (r.gov_type_scope = 'local' AND l.type BETWEEN 1 AND 3))
     WHERE r.recipe_id IN (%1$s)
       AND l.canonical_govid IN (%2$s)
       AND l.year IN (%3$s)
       AND l.amt <> 0
       AND NOT EXISTS (
         SELECT 1 FROM %4$s v
         WHERE v.canonical_govid = l.canonical_govid
           AND v.year = l.year
           AND v.item_code = l.item_code
       )
     GROUP BY 1, 2
     ORDER BY 1, 2",
    .sql_lit_chr(candidates), .sql_lit_chr(govid),
    paste(as.integer(years), collapse = ","), long_view
  )
  tibble::as_tibble(DBI::dbGetQuery(con, sql))
}
```

- [ ] **Step 5: Run to verify they pass**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(filter = "recipes")' 2>&1 | tail -30
```

Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add R/suggestions.R R/spending.R tests/testthat/test-recipes.R
git commit -m "feat: measure structurally-suppressed recipe component dollars (#9)"
```

---

### Task 2: Widen `.build_suggestions()` and add the four fields

**Files:**
- Modify: `R/suggestions.R:54-132` (`.build_suggestions()`) and its header comment block at lines 1-31
- Modify: `R/spending.R:396-398` (call site)
- Test: `tests/testthat/test-recipes.R`

**Interfaces:**
- Consumes: `.suppressed_components(con, candidates, govid, years, long_view)` and `.select_long_view(view_base, basis)` from Task 1
- Produces: `.build_suggestions(con, govid, years, category, result, basis, flow_prefixes, long_view)` — one new trailing argument. Each returned suggestion is a list with the five existing keys (`recipe_id`, `label`, `available_years`, `hint`, `ig_recipe_id`) plus:
  - `trigger` — chr(1), `"empty_year"` or `"suppressed_component"`. `"empty_year"` wins when both apply.
  - `suppressed_amount` — dbl(1), full US dollars summed across requested years, `0` when none.
  - `suppressed_years` — integer vector, sorted, `integer(0)` when none.
  - `suppressed_codes` — chr vector, sorted unique, `character(0)` when none.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-recipes.R`:

```r
test_that("uscogdata#9: Public Welfare signposts its suppressed E67/E68 dollars", {
  # The bug: E74/E79 return rows for FY2011, so there is no row-absence gap,
  # so nothing fired -- while E67 ($1,803,872,000) and E68 ($271,589,000) were
  # dropped for being aggregate-published. LA County reports $3,185,943,000
  # and omits $2,075,461,000, a 39% understatement, silently.
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("061037123085", years = 2011L, category = "Public Welfare"))
  sugg <- attr(r, "provenance")$suggestions

  expect_length(sugg, 2L)
  ids <- vapply(sugg, function(s) s$recipe_id, character(1))
  expect_setequal(ids, c("welfare_cash_e67_wide", "welfare_cash_e68_wide"))

  e67 <- sugg[[which(ids == "welfare_cash_e67_wide")]]
  expect_equal(e67$trigger, "suppressed_component")
  expect_equal(e67$suppressed_amount, 1803872000)
  expect_equal(e67$suppressed_years, 2011L)
  expect_equal(e67$suppressed_codes, "E67")
  expect_equal(e67$hint, "re-run with recipe = 'welfare_cash_e67_wide'")

  e68 <- sugg[[which(ids == "welfare_cash_e68_wide")]]
  expect_equal(e68$trigger, "suppressed_component")
  expect_equal(e68$suppressed_amount, 271589000)
  expect_equal(e68$suppressed_codes, "E68")
})

test_that("uscogdata#9: an empty_year fire keeps its trigger and gains the dollars", {
  # Corrections is the case that already worked: zero rows in FY2011, so the
  # row-absence path fires. It must keep firing, keep trigger = "empty_year",
  # keep its IG counterpart -- and now also report what was suppressed.
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("061037123085", years = 2011L, category = "Corrections"))
  sugg <- attr(r, "provenance")$suggestions

  expect_length(sugg, 3L)
  ids <- vapply(sugg, function(s) s$recipe_id, character(1))
  expect_setequal(ids, c("corrections_combined", "corrections_capital_combined",
                         "corrections_other_capital_combined"))
  expect_true(all(vapply(sugg, function(s) s$trigger, character(1)) == "empty_year"))

  cc <- sugg[[which(ids == "corrections_combined")]]
  expect_equal(cc$suppressed_amount, 1371460000)
  expect_equal(cc$suppressed_codes, "E05")
  expect_equal(cc$ig_recipe_id, "corrections_ig_local_combined")
})

test_that("uscogdata#9: the revenue verb inherits the same trigger", {
  # Alaska state FY2011 Miscellaneous Revenue reports $943,842,000 from
  # U11/U20/U30 while dropping $1,899,995,000 of aggregate-published `U4-`
  # rents and royalties -- the omission is LARGER than the reported figure.
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_revenue("020000227749", years = 2011L,
                category = "Miscellaneous Revenue"))
  sugg <- attr(r, "provenance")$suggestions

  expect_length(sugg, 1L)
  expect_equal(sugg[[1]]$recipe_id, "rents_royalties_u4_wide")
  expect_equal(sugg[[1]]$trigger, "suppressed_component")
  expect_equal(sugg[[1]]$suppressed_amount, 1899995000)
  expect_equal(sugg[[1]]$suppressed_codes, "U4-")
  # A revenue recipe must never be handed an M/L expenditure counterpart.
  expect_null(sugg[[1]]$ig_recipe_id)
})

test_that("uscogdata#9: no partial-coverage fire in a modern year", {
  skip_if_no_corpus()
  r <- cog_spending("061037123085", years = 2019L, category = "Public Welfare")
  expect_length(attr(r, "provenance")$suggestions, 0L)
})

test_that("uscogdata#9: leaf-and-classified wide-era families never fire", {
  # higher_ed_e18_wide and general_gov_e89_wide are the control group: their
  # components (E16/E18, E85/E89) are ordinary classified leaves even in the
  # wide era, so widening the trigger must leave them silent. This is the
  # measurement that refutes "it would fire on every category in every legacy
  # year" -- corpus-wide on the fixture, these two produce zero suppressed rows.
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n
     FROM long l
     JOIN harmonization_recipes r
       ON l.item_code = r.component_code
      AND l.year BETWEEN r.year_min AND r.year_max
     WHERE r.recipe_id IN ('higher_ed_e18_wide', 'general_gov_e89_wide')
       AND l.amt <> 0
       AND NOT EXISTS (
         SELECT 1 FROM spending_long_harmonized v
         WHERE v.canonical_govid = l.canonical_govid
           AND v.year = l.year AND v.item_code = l.item_code)")$n
  expect_equal(as.integer(n), 0L)
})
```

- [ ] **Step 2: Run to verify they fail**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(filter = "recipes")' 2>&1 | tail -40
```

Expected: FAIL — the Public Welfare and revenue tests get `length(sugg) == 0`; the Corrections test fails on the missing `suppressed_amount`. The two negative-control tests should already PASS.

- [ ] **Step 3: Replace the body of `.build_suggestions()`**

In `R/suggestions.R`, change the signature and everything from `result_years <-` through the closing `.attach_ig_counterparts(...)` call. The `candidates` query (lines 70-81) is **unchanged** — do not touch it.

```r
.build_suggestions <- function(con, govid, years, category, result, basis,
                                flow_prefixes, long_view) {
  if (!identical(basis, "harmonized") || is.null(category)) return(list())

  # ... candidates query unchanged ...
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
  # still be missing dollars.
  supp <- .suppressed_components(con, candidates, govid, years, long_view)

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
```

- [ ] **Step 4: Update the file header comment**

In `R/suggestions.R`, replace the first paragraph (lines 1-5) so the file's stated contract matches its behavior:

```r
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
```

- [ ] **Step 5: Update the call site in `R/spending.R`**

At lines 396-398, pass the long view:

```r
    suggestions <- .build_suggestions(con, govid, years, category,
                                       direct_leg_result,
                                       resolved$basis, flow_prefixes,
                                       .select_long_view(view_base, resolved$basis))
```

- [ ] **Step 6: Run the recipes tests**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(filter = "recipes")' 2>&1 | tail -30
```

Expected: PASS, 0 failures.

- [ ] **Step 7: Run the full suite — this is the regression gate**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(reporter = "summary")' 2>&1 | tail -30
```

Expected: 0 FAIL, and PASS count = Task 0 baseline plus the new tests. The three pre-verified `expect_length(suggestions, 0L)` assertions (`test-recipes.R:196`, `test-recipes.R:82`, `test-expenditure-concept.R:293`) must still pass. If any fails, **stop and report** — it means the trigger is firing somewhere the measurement said it would not.

- [ ] **Step 8: Commit**

```bash
git add R/suggestions.R R/spending.R tests/testthat/test-recipes.R
git commit -m "fix: signpost aggregate-suppressed components in a category that still has rows (#9)"
```

---

### Task 3: Surface the dollars in the cli message and `cog_explain()`

**Files:**
- Modify: `R/suggestions.R:237-251` (`.inform_suggestions()`)
- Modify: `R/explain.R:125-132`
- Test: `tests/testthat/test-recipes.R`

**Interfaces:**
- Consumes: the suggestion fields from Task 2
- Produces: no new functions; `.inform_suggestions()` and `cog_explain()` render `suppressed_amount` / `suppressed_years` / `suppressed_codes` when `suppressed_amount > 0`

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-recipes.R`:

```r
test_that("uscogdata#9: the cli message reports the suppressed dollars", {
  skip_if_no_corpus()
  expect_message(
    cog_spending("061037123085", years = 2011L, category = "Public Welfare"),
    "1,803,872,000", fixed = TRUE)
  expect_message(
    cog_spending("061037123085", years = 2011L, category = "Public Welfare"),
    "FY2011", fixed = TRUE)
  expect_message(
    cog_spending("061037123085", years = 2011L, category = "Public Welfare"),
    "E67", fixed = TRUE)
})

test_that("uscogdata#9: cog_explain() reports the suppressed dollars", {
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("061037123085", years = 2011L, category = "Public Welfare"))
  out <- paste(capture.output(cog_explain(r), type = "message"),
               capture.output(cog_explain(r)), collapse = "\n")
  expect_match(out, "271,589,000", fixed = TRUE)
})
```

- [ ] **Step 2: Run to verify they fail**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(filter = "recipes")' 2>&1 | tail -30
```

Expected: FAIL — no dollar figures in either output.

- [ ] **Step 3: Extend `.inform_suggestions()`**

Replace the body in `R/suggestions.R`:

```r
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
```

> The header changed from "Coverage gap detected for the requested years" because a partial-coverage fire is not a gap — the year has rows, they are just short. Verified 2026-08-04: no test in `tests/` asserts the old string, so this is safe.

- [ ] **Step 4: Extend the `cog_explain()` renderer**

Replace lines 125-132 of `R/explain.R`:

```r
  if (length(prov$suggestions) > 0L) {
    cli::cli_h2("Suggestions")
    sugg_lines <- vapply(prov$suggestions, function(s) {
      line <- sprintf("%s -- %s (years %s-%s): %s", s$recipe_id, s$label,
              s$available_years[1], s$available_years[2], s$hint)
      if (isTRUE(s$suppressed_amount > 0)) {
        line <- paste0(line, sprintf(" [$%s excluded from %s: %s]",
          formatC(s$suppressed_amount, format = "f", digits = 0, big.mark = ","),
          paste0("FY", s$suppressed_years, collapse = ", "),
          paste(s$suppressed_codes, collapse = ", ")))
      }
      line
    }, character(1))
    cli::cli_ul(sugg_lines)
  }
```

- [ ] **Step 5: Run to verify they pass**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(filter = "recipes|explain")' 2>&1 | tail -30
```

Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add R/suggestions.R R/explain.R tests/testthat/test-recipes.R
git commit -m "feat: report suppressed component dollars in the signpost message (#9)"
```

---

### Task 4: Document the contract — schema, NEWS, roxygen

**Files:**
- Modify: `inst/schemas/provenance-v1.json:36`
- Modify: `NEWS.md` (new section at top, under the `# uscogdata 0.1.0 (development)` heading)
- Test: `tests/testthat/test-recipes.R`

**Interfaces:**
- Consumes: the suggestion fields from Task 2
- Produces: no code interfaces; the schema is the published contract cog-api reads against

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-recipes.R`:

```r
test_that("the provenance schema documents the suggestion trigger fields", {
  sch <- jsonlite::fromJSON(
    system.file("schemas", "provenance-v1.json", package = "uscogdata"),
    simplifyVector = FALSE)
  props <- sch$properties$suggestions$items$properties
  expect_true(all(c("trigger", "suppressed_amount", "suppressed_years",
                    "suppressed_codes") %in% names(props)))
  expect_setequal(unlist(props$trigger$enum),
                  c("empty_year", "suppressed_component"))
})
```

- [ ] **Step 2: Run to verify it fails**

```bash
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(filter = "recipes")' 2>&1 | tail -20
```

Expected: FAIL — `sch$properties$suggestions$items` is NULL.

- [ ] **Step 3: Replace the `suggestions` property in `inst/schemas/provenance-v1.json`**

Replace line 36 (`"suggestions":    { "type": "array" },`) with:

```json
    "suggestions": {
      "type": "array",
      "description": "Harmonization recipes that would fill incomplete coverage in the requested years for this government. Empty on a healthy query, on an un-scoped (category = NULL) query, on basis = 'raw', and on a recipe = query (which resolves its own coverage).",
      "items": {
        "type": "object",
        "required": ["recipe_id", "label", "available_years", "hint", "trigger",
                     "suppressed_amount", "suppressed_years", "suppressed_codes"],
        "properties": {
          "recipe_id": { "type": "string" },
          "label": { "type": "string" },
          "available_years": {
            "type": "array",
            "items": { "type": "integer" },
            "description": "[year_min, year_max] of the recipe's component coverage."
          },
          "hint": { "type": "string" },
          "ig_recipe_id": {
            "type": ["string", "null"],
            "description": "The intergovernmental (M/L) counterpart recipe covering the same function suffixes, or null. Never set for revenue recipes."
          },
          "trigger": {
            "type": "string",
            "enum": ["empty_year", "suppressed_component"],
            "description": "Why this fired. 'empty_year': the result has no rows at all in a requested year. 'suppressed_component': the result HAS rows, but a component code carries dollars the verb's long view structurally excludes -- aggregate-published, or absent from summary_categories. 'empty_year' wins when both apply, being the stronger claim; the suppressed_* fields are populated either way."
          },
          "suppressed_amount": {
            "type": "number",
            "description": "Full US dollars this government holds in the recipe's component codes that the result excludes, summed across the requested years. 0 when nothing is suppressed."
          },
          "suppressed_years": {
            "type": "array",
            "items": { "type": "integer" },
            "description": "The requested years contributing to suppressed_amount."
          },
          "suppressed_codes": {
            "type": "array",
            "items": { "type": "string" },
            "description": "The excluded component item codes, sorted."
          }
        }
      }
    },
```

- [ ] **Step 4: Add the NEWS.md entry**

Insert immediately after the `# uscogdata 0.1.0 (development)` line:

```markdown
## Signposting now catches partially-suppressed categories

* A coverage suggestion used to fire only when a category returned **no rows
  at all** in a requested year. That missed the more dangerous case: a
  category that still returns rows while silently dropping component codes
  the wide era publishes only as aggregates (#9). `cog_spending(category =
  "Public Welfare")` for FY2011 returned a plausible figure that omitted
  `E67`/`E68` entirely -- for Los Angeles County, $2,075,461,000 of a true
  $5,261,404,000, a 39% understatement, with `provenance$suggestions` empty.
* Suggestions now also fire on **partial** coverage, and every suggestion
  carries `trigger` (`"empty_year"` or `"suppressed_component"`),
  `suppressed_amount`, `suppressed_years` and `suppressed_codes`, so a caller
  can see how much is missing and decide whether to re-run with the recipe.
* `cog_revenue()` gets the same fix through the shared verb path. Alaska's
  FY2011 `Miscellaneous Revenue` reported $943,842,000 while dropping
  $1,899,995,000 of aggregate-published `U4-` rents and royalties.
* The trigger stays recipe-driven, so it only fires where a harmonization
  recipe actually exists to name the fix. Measured on the bundled fixture,
  every fire lands in the wide era; `higher_ed_e18_wide` and
  `general_gov_e89_wide` stay silent, because their components are ordinary
  classified leaves even pre-2012.
```

- [ ] **Step 5: Regenerate docs and run the full suite**

```bash
/usr/bin/Rscript -e 'devtools::document()'
/usr/bin/Rscript -e 'devtools::load_all("."); testthat::test_local(reporter = "summary")' 2>&1 | tail -30
```

Expected: 0 FAIL. `devtools::document()` should produce no `man/` changes (all edits are `@noRd` or non-roxygen); if it does, include them in the commit.

- [ ] **Step 6: Commit**

```bash
git add inst/schemas/provenance-v1.json NEWS.md tests/testthat/test-recipes.R man/
git commit -m "docs: document the suggestion trigger and suppressed-dollar fields (#9)"
```

---

### Task 5: Ship the reader — check, push, PR

**Files:** none (verification + git)

**Interfaces:**
- Consumes: everything from Tasks 1-4
- Produces: a green CI run and an open PR on `gitea.civilytics.org/Civilytics/uscogdata`

- [ ] **Step 1: Run R CMD check**

```bash
/usr/bin/Rscript -e 'rcmdcheck::rcmdcheck(args = c("--no-manual", "--as-cran"), error_on = "warning")' 2>&1 | tail -40
```

Expected: 0 errors, 0 warnings. Notes about fixture size are pre-existing.

- [ ] **Step 2: Confirm the file-length constraint still holds**

```bash
wc -l R/suggestions.R R/spending.R R/explain.R
```

Expected: `R/suggestions.R` under 400 lines. If it has crossed, split `.suppressed_components()` into `R/suppression.R` and re-run the suite before continuing.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin fix/partial-coverage-signposting-9
tea pr create --title "fix: signpost partially-suppressed categories (#9)" \
  --description "Closes #9.

\`.build_suggestions()\` fired only when a category returned zero rows in a requested year. Public Welfare is the failure mode that missed: E74/E79 still return rows for legacy years, so no row-absence gap existed, while aggregate-published E67/E68 were dropped by \`spending_long\`'s \`NOT is_aggregate\` filter. LA County FY2011 reported \$3,185,943,000 and omitted \$2,075,461,000 -- a 39% understatement -- with \`provenance\$suggestions\` empty.

A recipe now also qualifies when a component code carries dollars the verb's own long view structurally excludes, measured per government by anti-joining the real view. Each suggestion carries \`trigger\`, \`suppressed_amount\`, \`suppressed_years\` and \`suppressed_codes\`.

\`cog_revenue()\` inherits it: Alaska FY2011 Miscellaneous Revenue dropped \$1,899,995,000 of \`U4-\`.

Blast radius measured on the bundled fixture: every fire lands in the wide era, none in 2012/2019/2020, and the leaf-and-classified control families (\`higher_ed_e18_wide\`, \`general_gov_e89_wide\`) stay silent."
```

- [ ] **Step 4: Wait for CI green, then merge**

```bash
tea pr list
```

Report the PR number and CI status to the user. **Do not merge without confirming CI is green** — merging is what cog-api's next build picks up.

---

### Task 6: cog-api — assert the fields survive the envelope, then deploy

**Files:**
- Modify: `~/Nextcloud/Civilytics/Code/Civilytics/cog-api/api/tests/testthat/test-handlers-governments.R` (append near the existing suggestions test at line 162)

**Interfaces:**
- Consumes: the merged reader from Task 5. cog-api needs **no handler code change** — `prov$suggestions` is lifted verbatim into the envelope at `api/R/handlers_query.R:100` and `api/R/handlers_governments.R:131,195,317`.
- Produces: a deployed API whose `/spending` responses carry the new fields

- [ ] **Step 1: Confirm the reader ref is not pinned to a stale SHA**

cog-api's CI and build clone uscogdata at `USCOGDATA_REF` (a Gitea repo variable, default `main` — see `.gitea/workflows/ci.yml:99-121`).

```bash
cd ~/Nextcloud/Civilytics/Code/Civilytics/cog-api
tea api -X GET /repos/Civilytics/cog-api/actions/variables
```

Expected: `USCOGDATA_REF` is absent or `main`. **If it is pinned to a commit SHA, stop and report to the user** — the deploy will silently ship the old reader, and every assertion below will fail for the wrong reason.

- [ ] **Step 2: Write the failing test**

Append to `api/tests/testthat/test-handlers-governments.R`:

```r
test_that("suppressed-component suggestion fields survive the envelope (uscogdata#9)", {
  # LA County FY2011 Public Welfare returns rows but drops aggregate-published
  # E67/E68. The reader signposts it; the envelope must not flatten the detail
  # away, because a Tableau consumer only ever sees the envelope.
  res <- handle_gov_spending("061037123085", years = "2011",
                             category = "Public Welfare",
                             adjust = NULL, base_year = NULL, per_capita = NULL,
                             subtype = NULL, limit = "1000", page = "0")
  ids <- vapply(res$suggestions, function(s) s$recipe_id, character(1))
  expect_true("welfare_cash_e67_wide" %in% ids)

  hit <- res$suggestions[[which(ids == "welfare_cash_e67_wide")]]
  expect_equal(hit$trigger, "suppressed_component")
  expect_equal(hit$suppressed_amount, 1803872000)
  expect_equal(hit$suppressed_codes, "E67")
})
```

- [ ] **Step 3: Install the merged reader locally and run the test**

```bash
cd ~/Nextcloud/Civilytics/Code/Civilytics/cog-api
/usr/bin/Rscript -e 'remotes::install_local("../cog_explorer/uscogdata", upgrade = "never")'
cd api/tests/testthat && /usr/bin/Rscript -e 'testthat::test_local(filter = "handlers-governments")' 2>&1 | tail -30
```

Expected: PASS. If it fails with `length(ids) == 0`, the installed reader is stale — re-run the install step.

- [ ] **Step 4: Run the full cog-api suite**

```bash
cd ~/Nextcloud/Civilytics/Code/Civilytics/cog-api/api/tests/testthat
/usr/bin/Rscript -e 'testthat::test_local(reporter = "summary")' 2>&1 | tail -30
```

Expected: 0 FAIL. Record the count.

- [ ] **Step 5: Commit, push, PR**

```bash
cd ~/Nextcloud/Civilytics/Code/Civilytics/cog-api
git checkout -b test/suppressed-component-fields
git add api/tests/testthat/test-handlers-governments.R
git commit -m "test: assert suppressed-component suggestion fields survive the envelope (uscogdata#9)"
git push -u origin test/suppressed-component-fields
tea pr create --title "test: assert uscogdata#9 suggestion fields survive the envelope" \
  --description "uscogdata#9 adds \`trigger\`, \`suppressed_amount\`, \`suppressed_years\` and \`suppressed_codes\` to each \`prov\$suggestions\` entry. cog-api lifts \`prov\$suggestions\` verbatim, so no handler change is needed -- this pins that pass-through so a future envelope refactor cannot silently drop the detail.

Merging this is the prod deploy that picks up the new reader."
```

- [ ] **Step 6: Merge after CI green, then verify the live endpoint**

> Merging a cog-api PR **is** the production deploy, and `deploy.yml` does not wait for CI. Confirm CI is green *before* merging, not after.

```bash
tea pr list
# after merge + deploy settles:
curl -s "https://<cog-api-host>/v1/governments/061037123085/spending?years=2011&category=Public%20Welfare" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['suggestions'], indent=2))"
```

Expected: two suggestions, `welfare_cash_e67_wide` carrying `"suppressed_amount": 1803872000`. Report the live output to the user.

---

### Task 7: Close out the issues

**Files:** none (issue tracker)

**Interfaces:**
- Consumes: the merged and deployed work from Tasks 5-6
- Produces: uscogdata#9 closed with a corrected record

- [ ] **Step 1: Comment on uscogdata#9 with the resolution**

```bash
cd ~/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata
tea comment 9 "**Fixed.** The trigger was the problem, not the crosswalk.

\`.build_suggestions()\` already identified \`welfare_cash_e67_wide\` and \`welfare_cash_e68_wide\` as candidates -- \`J67\`/\`J68\` are Public Welfare members, so the candidate query matched. It then threw them away at the \`gap_years\` early return, because E74/E79 returned rows and there was no empty year to detect.

A recipe now also qualifies when a component code carries dollars the verb's own long view structurally excludes -- aggregate-published, or absent from \`summary_categories\`. Reachability is decided by anti-joining the real view rather than restating its WHERE clause, which is sound because no recipe component is ever renamed by harmonization (now asserted).

Each suggestion carries \`trigger\`, \`suppressed_amount\`, \`suppressed_years\`, \`suppressed_codes\`. \`cog_revenue()\` inherits the fix.

**On the 'would fire on every category in every legacy year' worry** -- measured, it does not. Candidates stay gated on the 24-recipe catalog, so it only fires where an actionable recipe exists. On the bundled fixture every fire lands in the wide era, none in 2012/2019/2020, and \`higher_ed_e18_wide\`/\`general_gov_e89_wide\` never fire at all because E18/E89 are ordinary classified leaves pre-2012.

**The 'minor' sub-item is withdrawn, not implemented.** \`aggregate_fallback\` is no longer vestigial: \`.build_verb_sql()\` uses \`bool_or(is_aggregate)\` (R/spending.R:611), and \`ig_long\` deliberately keeps aggregate rows, so the flag is live for the intergovernmental leg -- \`test-expenditure-concept.R:99\` asserts aggregate-sourced IG dollars report TRUE. Removing it would break that disclosure.

**Reproduction, now signposted** (bundled fixture, LA County):
\`\`\`r
r <- cog_spending(\"061037123085\", years = 2011, category = \"Public Welfare\")
attr(r, \"provenance\")\$suggestions[[1]]\$suppressed_amount  # 1803872000
\`\`\`"
```

- [ ] **Step 2: Close the issue**

```bash
tea issue close 9
tea issue 9 | head -5
```

Expected: state `closed`.

- [ ] **Step 3: Restore the stashed fixture changes**

```bash
git checkout ci/apt-https
git stash list
git stash pop
git status --short
```

Expected: the two fixture files modified again, as they were before Task 0. Report to the user that they are restored and still uncommitted.

---

## Self-Review

**Spec coverage** — every element of the approved design maps to a task:

| Design element | Task |
|---|---|
| Second trigger in `.build_suggestions()`, candidate query untouched | 2 |
| Anti-join the real view, not a restated predicate | 1 |
| Structural invariant (no renamed components) asserted | 1 |
| Scoping-excluded ≠ suppressed; F-007 stays out | 1 (roxygen), 2 (control test) |
| Four new suggestion fields, `empty_year` precedence | 2 |
| Both verbs via the shared call site | 2 (revenue test) |
| cli message + `cog_explain()` | 3 |
| Provenance schema documents the fields (no v1 bump) | 4 |
| LA County / Alaska / Corrections / 2019 / control tests | 2, 3 |
| cog-api pass-through + redeploy | 6 |
| Close #9, withdraw the `aggregate_fallback` sub-item | 7 |

**Placeholder scan** — no TBD/TODO; every code step carries real code; every assertion carries a measured value.

**Type consistency** — `.suppressed_components()` returns `recipe_id`/`year`/`suppressed_amount`/`suppressed_codes` in Task 1 and is consumed under exactly those names in Task 2. `.select_long_view(view_base, basis)` is defined in Task 1 and called with that signature in Task 2. `suppressed_codes` is comma-joined **inside** the tibble (Task 1) and split into a character vector **for the suggestion** (Task 2) — deliberate, and the tests assert both shapes correctly.
