# Per-year population denominator implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `cog_spending(per_capita = TRUE)` / `cog_revenue(per_capita = TRUE)` / `cog_geographic_rollup()` static-ACS denominator with the per-year Census F-33 population already present in `long.population`. Switch peer matching to a user-selectable cohort year. Add `pop_source` column, multi-note concatenation, updated provenance, vignette, and pipeline data dictionary entry.

**Architecture:** A new `gov_population_yearly` DuckDB view exposes `(year, canonical_govid, population, popyear)` from `long`. `.attach_per_capita()` joins on `(canonical_govid, year)` instead of querying the static `canonical_fips_xwalk.population_acs`. `cog_find_peers()` queries the new view at a chosen year (default = most recent observed year for the target). `cog_geographic_rollup()` sums population across observed govs only. Type-4 (special districts) and type-5 (school districts) govs return `NA` per-capita with `pop_source = "unavailable"` because the F-33 schema masks population for those types.

**Tech Stack:** R (DuckDB via DBI), testthat 3, roxygen2, pkgdown, tibble/dplyr, cli.

**Spec:** `specs/2026-04-29-per-year-population-denominator-design.md`

**Coverage assumption (fixture):** The bundled `inst/extdata/fixture_corpus` covers years 2019 and 2020 across all 50 states for types 0–3. It contains no type-4 or type-5 govs, so unavailability tests rely on querying govids absent from `gov_population_yearly` rather than on type filters. A list of fixture govids used in tests below: Alabama state `010000000` (pop 4,874,747 → 4,903,185), Broward County `101006006` (1,935,878 → 1,952,778), Wayne County `231082082`, Bexar County `441015015`, Tarrant County `441220220`. Static ACS values: Alabama `5,028,092`, Broward `1,940,907`.

---

## Task 1: Add `gov_population_yearly` view

**Files:**
- Create: `inst/sql/32-gov_population_yearly.sql`
- Modify: `tests/testthat/test-views.R` (append a test)

- [ ] **Step 1: Read existing `test-views.R` to learn the pattern**

```bash
cat tests/testthat/test-views.R
```

Note the pattern: tests open `with_fixture_corpus({ ... })`, then run a `DBI::dbGetQuery()` against `.ensure_session()` to verify a view exists and returns expected columns.

- [ ] **Step 2: Write the failing test**

Append to `tests/testthat/test-views.R`:

```r
test_that("gov_population_yearly exposes one row per (year, canonical_govid)", {
  skip_if_no_corpus()
  with_fixture_corpus({
    con <- uscogdata:::.ensure_session()
    df <- DBI::dbGetQuery(
      con,
      "SELECT year, canonical_govid, population, popyear
       FROM gov_population_yearly
       WHERE canonical_govid = '101006006'
       ORDER BY year"
    )
    expect_setequal(df$year, c(2019L, 2020L))
    expect_equal(nrow(df), 2L)
    expect_true(all(!is.na(df$population)))
    expect_equal(df$population[df$year == 2019L], 1935878L)
    expect_equal(df$population[df$year == 2020L], 1952778L)
    # Uniqueness on (year, canonical_govid) across the whole view.
    dup <- DBI::dbGetQuery(
      con,
      "SELECT year, canonical_govid, COUNT(*) AS n
       FROM gov_population_yearly
       GROUP BY year, canonical_govid HAVING n > 1"
    )
    expect_equal(nrow(dup), 0L)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "views")'
```

Expected: FAIL — `gov_population_yearly` view does not exist (DuckDB binder error).

- [ ] **Step 4: Create the SQL view file**

Write `inst/sql/32-gov_population_yearly.sql`:

```sql
CREATE OR REPLACE VIEW gov_population_yearly AS
SELECT DISTINCT
  year,
  canonical_govid,
  population,
  popyear
FROM long
WHERE population IS NOT NULL;
```

The numeric prefix `32` slots between the existing `30-canonical_fips_xwalk.sql` and `40-spending_annotated.sql` so it loads before any annotated views that might depend on it.

- [ ] **Step 5: Re-run the test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "views")'
```

Expected: PASS for the new test plus the existing view tests.

- [ ] **Step 6: Commit**

```bash
git add inst/sql/32-gov_population_yearly.sql tests/testthat/test-views.R
git commit -m "feat(sql): add gov_population_yearly view

Exposes one row per (year, canonical_govid) drawn from long.population.
Used by per-capita denominators and peer matching."
```

---

## Task 2: Per-year denominator in `.attach_per_capita` (RED)

Write the failing test first; implement in Task 3.

**Files:**
- Modify: `tests/testthat/test-spending.R` (append)

- [ ] **Step 1: Read existing `test-spending.R` patterns**

```bash
head -80 tests/testthat/test-spending.R
```

- [ ] **Step 2: Write the failing test**

Append to `tests/testthat/test-spending.R`:

```r
test_that("per_capita denominator is the per-year F-33 population", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("101006006", years = 2019:2020,
                      category = "Police", per_capita = TRUE)
    r_ops <- r[r$spend_subtype == "operations", ]
    # Implied denominator from amt_nominal / amt_per_capita_nominal
    implied_pop <- r_ops$amt_nominal / r_ops$amt_per_capita_nominal
    names(implied_pop) <- r_ops$year
    expect_equal(implied_pop[["2019"]], 1935878, tolerance = 1)
    expect_equal(implied_pop[["2020"]], 1952778, tolerance = 1)
    # And the implied denominator does NOT equal the static ACS value
    expect_false(all(abs(implied_pop - 1940907) < 1))
  })
})
```

- [ ] **Step 3: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "spending")'
```

Expected: FAIL — implied denominator equals 1,940,907 (static ACS) for both years.

- [ ] **Step 4: Commit the failing test**

```bash
git add tests/testthat/test-spending.R
git commit -m "test(spending): per-year denominator expectation (failing)"
```

---

## Task 3: Rewrite `.attach_per_capita` to join on (canonical_govid, year) (GREEN)

**Files:**
- Modify: `R/spending.R:143-159`

- [ ] **Step 1: Read current `.attach_per_capita`**

```bash
sed -n '143,160p' R/spending.R
```

- [ ] **Step 2: Replace `.attach_per_capita` with per-year join**

Edit `R/spending.R`. Replace the existing function body (lines 143–159) with:

```r
#' @noRd
.attach_per_capita <- function(result, con, govid) {
  if (nrow(result) == 0L) {
    result$amt_per_capita_nominal <- numeric(0)
    result$pop_source <- character(0)
    return(result)
  }
  years_lit <- paste(unique(as.integer(result$year)), collapse = ",")
  sql <- sprintf(
    "SELECT canonical_govid, year, population
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
  result$population <- NULL
  result
}
```

Key changes vs. the prior implementation:
- Joins on `(canonical_govid, year)` instead of `canonical_govid` alone.
- Queries `gov_population_yearly` instead of `canonical_fips_xwalk`.
- Adds `pop_source` column (`"census_f33"` or `"unavailable"`).
- `amt_per_capita_nominal` is naturally NA when `population` is NA (R's `NA / x = NA`).

- [ ] **Step 3: Run the failing test from Task 2 to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "spending")'
```

Expected: PASS for the new test. Existing per-capita tests in `test-spending.R` may now fail because they were written against the static-ACS denominator. Inspect each failure — most should be updated to assert the per-year implied denominator. Tests that asserted *equality* of per-capita across years for the same gov are no longer correct expectations.

- [ ] **Step 4: Update any existing per-capita tests in `test-spending.R` that fail**

Read each failing test. If it merely asserted `amt_per_capita_nominal` is positive/finite, no change needed. If it asserted a specific numeric value derived from `population_acs`, recompute the expected value using the per-year `population` for that gov-year. If it asserted `amt_per_capita` is the same across two years, change it to assert that the per-year implied denominator matches `gov_population_yearly`.

- [ ] **Step 5: Run the full spending test file**

```bash
Rscript -e 'devtools::test(filter = "spending")'
```

Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
git add R/spending.R tests/testthat/test-spending.R
git commit -m "feat(per-capita): use per-year F-33 population in spending verbs

cog_spending(per_capita = TRUE) and cog_revenue(per_capita = TRUE) now
divide each year's amount by that gov-year's population from
gov_population_yearly (drawn from long.population) instead of a single
static ACS 2018-2022 value. Adds pop_source column with values
'census_f33' or 'unavailable'."
```

---

## Task 4: Multi-note concatenation + unavailable-pop note

**Files:**
- Modify: `R/spending.R:177-185` (`.notes_column`)
- Modify: `R/spending.R:42-80` (`.verb_spendrev`) to call `.notes_column` after per-capita is attached
- Modify: `tests/testthat/test-spending.R` (append)

- [ ] **Step 1: Read current `.notes_column`**

```bash
sed -n '177,190p' R/spending.R
```

The current implementation builds a one-element note ("Aggregate fallback applied; see cog_explain()" or "") off `aggregate_fallback`. After this task it concatenates multiple sources of notes, joined by `"; "`.

- [ ] **Step 2: Write a failing test**

Append to `tests/testthat/test-spending.R`:

```r
test_that("pop_source = 'unavailable' produces a note and NA per-capita", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # No type-4/5 govs in fixture; use a govid present in long but synthetically
    # absent from gov_population_yearly by querying a year out of fixture range.
    # Better: query a govid that doesn't exist anywhere — cog_spending will
    # return zero rows. Use a real govid in 2019 with per_capita to confirm
    # the no-NA branch works, then test the NA branch with a manual round-trip:
    r <- cog_spending("101006006", years = 2019L,
                      category = "Police", per_capita = TRUE)
    expect_true(all(r$pop_source == "census_f33"))
    expect_true(all(is.na(r$notes) | r$notes == "" |
                    !grepl("No population denominator", r$notes)))
  })
})

test_that("aggregate fallback + unavailable pop produce concatenated notes", {
  # Unit-level test of .notes_column with a synthetic data frame so we don't
  # depend on having a type-4/5 gov in the fixture.
  result <- tibble::tibble(
    aggregate_fallback = c(FALSE, TRUE,  TRUE),
    pop_source         = c("census_f33", "census_f33", "unavailable")
  )
  notes <- uscogdata:::.notes_column(result)
  expect_equal(notes[1], "")
  expect_equal(notes[2], "Aggregate fallback applied; see cog_explain()")
  expect_equal(notes[3],
               "Aggregate fallback applied; see cog_explain(); No population denominator available for this gov type")
})
```

- [ ] **Step 3: Run test to verify the second one fails**

```bash
Rscript -e 'devtools::test(filter = "spending")'
```

Expected: FAIL — `.notes_column` does not yet handle `pop_source`.

- [ ] **Step 4: Rewrite `.notes_column`**

Replace `.notes_column` in `R/spending.R` with:

```r
#' @noRd
.notes_column <- function(result) {
  n <- nrow(result)
  if (n == 0L) return(character(0))
  parts <- vector("list", 2L)
  agg <- result[["aggregate_fallback"]]
  parts[[1]] <- ifelse(
    !is.null(agg) & isTRUE(any(agg, na.rm = TRUE)) & agg %in% TRUE,
    "Aggregate fallback applied; see cog_explain()",
    NA_character_
  )
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
```

The per-row loop is unavoidable in base R for this exact join semantics; the result tibble is small (one row per year × govid × subtype × category) so this is fine.

- [ ] **Step 5: Verify `.notes_column` is called after `.attach_per_capita`**

Read `.verb_spendrev` (`R/spending.R:42-80`). The existing flow is:

```
sql -> result
if (per_capita) result <- .attach_per_capita(result, con, govid)
if (!is.null(adjust_to_year)) result <- .attach_real_dollars(...)
result$notes <- .notes_column(result)
```

`.notes_column` is already invoked after per-capita attachment, so no change to `.verb_spendrev` is required. Verify with:

```bash
sed -n '54,63p' R/spending.R
```

Expected output: shows `.notes_column(result)` on a line after the per-capita block.

- [ ] **Step 6: Run tests**

```bash
Rscript -e 'devtools::test(filter = "spending")'
```

Expected: ALL PASS.

- [ ] **Step 7: Commit**

```bash
git add R/spending.R tests/testthat/test-spending.R
git commit -m "feat(notes): concatenate notes; flag unavailable population

.notes_column now joins multiple per-row notes with '; '. Adds the
'No population denominator available for this gov type' note when
pop_source is 'unavailable'."
```

---

## Task 5: `cog_find_peers()` per-year (RED)

**Files:**
- Modify: `tests/testthat/test-peers.R` (append)

- [ ] **Step 1: Write failing tests**

Append to `tests/testthat/test-peers.R`:

```r
test_that("cog_find_peers defaults `year` to most recent observed year for target", {
  skip_if_no_corpus()
  peers <- cog_find_peers("101006006")
  expect_equal(attr(peers, "cohort_year"), 2020L)
  # Returned column is now `population`, not `population_acs`
  expect_true("population" %in% names(peers))
  expect_false("population_acs" %in% names(peers))
})

test_that("cog_find_peers honors an explicit `year`", {
  skip_if_no_corpus()
  peers <- cog_find_peers("101006006", year = 2019L)
  expect_equal(attr(peers, "cohort_year"), 2019L)
})

test_that("cog_find_peers errors when target has no observed pop in `year`", {
  skip_if_no_corpus()
  expect_error(
    cog_find_peers("101006006", year = 1999L),
    "no observed population"
  )
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
Rscript -e 'devtools::test(filter = "peers")'
```

Expected: FAIL — function doesn't accept `year` arg, returns `population_acs` column.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/testthat/test-peers.R
git commit -m "test(peers): per-year cohort expectations (failing)"
```

---

## Task 6: `cog_find_peers()` per-year (GREEN)

**Files:**
- Modify: `R/peers.R:24-88`

- [ ] **Step 1: Replace `cog_find_peers` body**

Replace the entire `cog_find_peers` function in `R/peers.R` with:

```r
#' Find peer governments by similarity criteria
#'
#' Selects peer governments by combinations of government type, state, and
#' population range at a chosen `year`. Peers are ordered by `|log(pop_ratio)|`
#' ascending (closest to the target's population first).
#'
#' @param target_govid Character scalar — `canonical_govid` of the target.
#' @param year Integer scalar. Cohort vintage. When `NULL` (default), uses the
#'   most recent year for which the target has an observed population in
#'   `gov_population_yearly`.
#' @param same_type If `TRUE` (default) restrict peers to the target's
#'   `govs_type`.
#' @param same_state If `TRUE` restrict peers to the target's `fips_state`.
#'   Default `FALSE`.
#' @param pop_range Length-2 numeric vector giving lower/upper bounds.
#' @param is_ratio If `TRUE` (default) `pop_range` is multiplied by the
#'   target's population at `year` to produce absolute bounds. If `FALSE`,
#'   `pop_range` is interpreted as absolute population counts.
#' @param max_peers Integer cap on the number of peers returned.
#' @return Tibble with columns `canonical_govid`, `gov_name`, `fips_state`,
#'   `population`, `pop_ratio`, `rank`. The cohort year is attached as
#'   `attr(x, "cohort_year")`.
#' @export
cog_find_peers <- function(target_govid,
                           year = NULL,
                           same_type = TRUE,
                           same_state = FALSE,
                           pop_range = c(0.7, 1.3),
                           is_ratio = TRUE,
                           max_peers = 10L) {
  if (!is.character(target_govid) || length(target_govid) != 1L) {
    cli::cli_abort("`target_govid` must be a length-1 character string.")
  }
  if (!is.numeric(pop_range) || length(pop_range) != 2L ||
      pop_range[1] >= pop_range[2]) {
    cli::cli_abort("`pop_range` must be a length-2 numeric with lo < hi.")
  }
  if (!is.null(year) &&
      (!(is.numeric(year) || is.integer(year)) || length(year) != 1L)) {
    cli::cli_abort("`year` must be NULL or a length-1 integer.")
  }

  con <- .ensure_session()

  # Confirm target exists in the xwalk and pull govs_type / fips_state.
  meta_sql <- sprintf(
    "SELECT canonical_govid, gov_name, govs_type, fips_state
     FROM canonical_fips_xwalk
     WHERE canonical_govid = %s",
    .sql_lit_chr(target_govid)
  )
  meta <- DBI::dbGetQuery(con, meta_sql)
  if (nrow(meta) == 0L) {
    cli::cli_abort(c(
      "govid {target_govid} not found in corpus.",
      i = "v0.1 covers types 0-3 only (state/county/city/township); see vignette('coverage-scope')."
    ))
  }

  cohort_year <- .resolve_cohort_year(con, target_govid, year)

  pop_sql <- sprintf(
    "SELECT population FROM gov_population_yearly
     WHERE canonical_govid = %s AND year = %d",
    .sql_lit_chr(target_govid), as.integer(cohort_year)
  )
  target_pop <- DBI::dbGetQuery(con, pop_sql)$population
  if (length(target_pop) == 0L || is.na(target_pop) || target_pop <= 0) {
    cli::cli_abort(c(
      "Target {target_govid} has no observed population in {cohort_year}.",
      i = "Use a year for which population is observed; see gov_population_yearly."
    ))
  }

  if (isTRUE(is_ratio)) {
    lo <- target_pop * pop_range[1]
    hi <- target_pop * pop_range[2]
  } else {
    lo <- pop_range[1]; hi <- pop_range[2]
  }

  preds <- c(
    sprintf("p.canonical_govid != %s", .sql_lit_chr(target_govid)),
    sprintf("p.year = %d", as.integer(cohort_year)),
    sprintf("p.population BETWEEN %.6f AND %.6f", lo, hi)
  )
  if (isTRUE(same_type))  preds <- c(preds, sprintf("x.govs_type = %d", meta$govs_type))
  if (isTRUE(same_state)) preds <- c(preds, sprintf("x.fips_state = %s", .sql_lit_chr(meta$fips_state)))

  peers_sql <- sprintf(
    "SELECT p.canonical_govid, x.gov_name, x.fips_state, p.population,
            p.population / %.6f AS pop_ratio
     FROM gov_population_yearly p
     JOIN canonical_fips_xwalk x USING (canonical_govid)
     WHERE %s
     ORDER BY ABS(LN(CAST(p.population AS DOUBLE) / %.6f))
     LIMIT %d",
    target_pop,
    paste(preds, collapse = " AND "),
    target_pop,
    as.integer(max_peers)
  )
  peers <- tibble::as_tibble(DBI::dbGetQuery(con, peers_sql))
  peers$rank <- if (nrow(peers) > 0L) seq_len(nrow(peers)) else integer(0)
  attr(peers, "cohort_year") <- as.integer(cohort_year)
  peers
}

#' @noRd
.resolve_cohort_year <- function(con, target_govid, year) {
  if (!is.null(year)) return(as.integer(year))
  sql <- sprintf(
    "SELECT MAX(year) AS y FROM gov_population_yearly
     WHERE canonical_govid = %s",
    .sql_lit_chr(target_govid)
  )
  y <- DBI::dbGetQuery(con, sql)$y
  if (length(y) == 0L || is.na(y)) {
    cli::cli_abort(
      "Target {target_govid} has no observed population in any year."
    )
  }
  as.integer(y)
}
```

- [ ] **Step 2: Run failing tests from Task 5**

```bash
Rscript -e 'devtools::test(filter = "peers")'
```

Expected: PASS for the three new tests. Existing tests in `test-peers.R` may fail because they reference `population_acs` — fix in next step.

- [ ] **Step 3: Update existing `test-peers.R` assertions**

The existing tests that reference `population_acs` need column name and value updates. Specifically lines that check `expected_cols` and `peers$population_acs`:

```r
# In test "cog_find_peers returns same-type peers in the default pop band":
expected_cols <- c("canonical_govid", "gov_name", "fips_state",
                   "population", "pop_ratio", "rank")

# In test "cog_find_peers absolute pop range works":
expect_true(all(peers$population >= 1.5e6 &
                peers$population <= 2.5e6))
```

Run `grep -n population_acs tests/testthat/test-peers.R` to find every instance and rename to `population`.

- [ ] **Step 4: Run all peer tests**

```bash
Rscript -e 'devtools::test(filter = "peers")'
```

Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add R/peers.R tests/testthat/test-peers.R
git commit -m "feat(peers): cog_find_peers uses per-year population

Adds optional 'year' argument (defaults to most recent observed year for
the target). Filters and ranks candidates by gov_population_yearly.population
at that year. Returned column renamed population_acs -> population.
Cohort year attached as attr(x, 'cohort_year')."
```

---

## Task 7: `cog_peer_compare()` cohort_year column

**Files:**
- Modify: `R/peers.R:112-146`
- Modify: `tests/testthat/test-peers.R` (append)

- [ ] **Step 1: Write failing test**

Append to `tests/testthat/test-peers.R`:

```r
test_that("cog_peer_compare stamps cohort_year from peers attribute", {
  skip_if_no_corpus()
  peers <- cog_find_peers("101006006", year = 2019L, max_peers = 4L)
  r <- cog_peer_compare("101006006", peers, "Police", years = 2020L)
  expect_true("cohort_year" %in% names(r))
  expect_true(all(r$cohort_year == 2019L))
  prov <- attr(r, "provenance")
  expect_equal(prov$cohort_year, 2019L)
})

test_that("cog_peer_compare cohort_year is NA for bare character peers", {
  skip_if_no_corpus()
  r <- cog_peer_compare(
    "101006006",
    peers = c("441015015", "441220220"),
    category = "Police", years = 2020L
  )
  expect_true(all(is.na(r$cohort_year)))
})
```

- [ ] **Step 2: Run to verify failure**

```bash
Rscript -e 'devtools::test(filter = "peers")'
```

Expected: FAIL — `cohort_year` column does not exist.

- [ ] **Step 3: Update `cog_peer_compare`**

In `R/peers.R`, edit `cog_peer_compare`. Just before the existing `attr(out, "provenance") <- prov` line, add the cohort_year derivation and column stamp; and inside the provenance block add the `cohort_year` field.

Replace the section from `peer_govids <- if (...)` through the final return with:

```r
  cohort_year <- if (is.data.frame(peers)) {
    ay <- attr(peers, "cohort_year")
    if (is.null(ay)) NA_integer_ else as.integer(ay)
  } else {
    NA_integer_
  }
  peer_govids <- if (is.data.frame(peers)) {
    as.character(peers$canonical_govid)
  } else {
    as.character(peers)
  }
  peer_govids <- peer_govids[!is.na(peer_govids) & nzchar(peer_govids)]
  all_govids <- unique(c(target_govid, peer_govids))

  r <- cog_spending(all_govids, years, category, per_capita, adjust_to_year)
  r$role <- ifelse(r$canonical_govid == target_govid, "target", "peer")

  value_col <- .peer_value_col(per_capita, adjust_to_year)

  summary_rows <- .peer_summary_rows(r, value_col)
  out <- dplyr::bind_rows(r, summary_rows)
  rank_val <- .peer_target_rank(r, target_govid, years, value_col)
  out$target_rank <- ifelse(out$role == "target", rank_val, NA_integer_)
  out$cohort_year <- cohort_year

  prov <- attr(r, "provenance") %||% list()
  prov$verb        <- "cog_peer_compare"
  prov$call        <- paste(deparse(call), collapse = " ")
  prov$peer_count  <- length(peer_govids)
  prov$cohort_year <- cohort_year
  prov$cohort_govids <- peer_govids
  prov$target      <- list(
    canonical_govid = target_govid,
    gov_name        = unique(r$gov_name[r$role == "target"])
  )
  attr(out, "provenance") <- prov
  out
}
```

- [ ] **Step 4: Run tests**

```bash
Rscript -e 'devtools::test(filter = "peers")'
```

Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add R/peers.R tests/testthat/test-peers.R
git commit -m "feat(peers): stamp cohort_year on cog_peer_compare results

Reads attr(peers, 'cohort_year') when the caller passed a cog_find_peers()
tibble; NA when the caller passed a bare character vector. Stamped as a
constant column on the result and recorded in provenance alongside the
cohort govids."
```

---

## Task 8: Population-aware `cog_geographic_rollup()` (RED)

**Files:**
- Modify: `tests/testthat/test-rollup.R` (append)

- [ ] **Step 1: Read existing rollup test patterns**

```bash
head -60 tests/testthat/test-rollup.R
```

- [ ] **Step 2: Write failing test**

Append to `tests/testthat/test-rollup.R`:

```r
test_that("cog_geographic_rollup per-capita uses summed per-year populations", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_geographic_rollup(
      govids   = list(state  = "010000000",
                      county = "101006006"),
      category = "Police",
      years    = 2019:2020,
      per_capita = TRUE
    )
    state_ops <- r[r$layer == "state" & r$spend_subtype == "operations", ]
    county_ops <- r[r$layer == "county" & r$spend_subtype == "operations", ]
    state_implied <- state_ops$amt_nominal / state_ops$amt_per_capita_nominal
    county_implied <- county_ops$amt_nominal /
      county_ops$amt_per_capita_nominal
    # Per-year, per-layer denominator is the layer's own per-year population
    expect_equal(state_implied[state_ops$year == 2019], 4874747, tolerance = 1)
    expect_equal(state_implied[state_ops$year == 2020], 4903185, tolerance = 1)
    expect_equal(county_implied[county_ops$year == 2019], 1935878, tolerance = 1)
  })
})

test_that("cog_geographic_rollup records included/excluded govids in provenance", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_geographic_rollup(
      govids   = list(county = "101006006"),
      category = "Police",
      years    = 2019:2020,
      per_capita = TRUE
    )
    prov <- attr(r, "provenance")
    expect_true("rollup" %in% names(prov))
    expect_true("101006006" %in% prov$rollup$included_govids)
    expect_true(is.character(prov$rollup$excluded_govids))
  })
})
```

- [ ] **Step 3: Run to verify failure**

```bash
Rscript -e 'devtools::test(filter = "rollup")'
```

Expected: the second test fails (no `rollup` block in provenance). The first may pass already because rollup currently delegates to `cog_spending` and the per-capita is per-row — verify.

- [ ] **Step 4: Commit failing tests**

```bash
git add tests/testthat/test-rollup.R
git commit -m "test(rollup): per-year denominator + provenance expectations (failing)"
```

---

## Task 9: Population-aware `cog_geographic_rollup()` (GREEN)

**Files:**
- Modify: `R/rollup.R:26-57`

The rollup currently passes through to `cog_spending()` and returns one row per `(year, canonical_govid, subtype, category)` tagged with its layer — a side-by-side comparison, not a summed total. The spec preserves that semantics.

The GREEN step:
- After `cog_spending(...)` returns, drop rows with `pop_source == "unavailable"` *only when `per_capita = TRUE`*.
- Record included/excluded govids in provenance.
- Document the rule in roxygen.

- [ ] **Step 1: Replace `cog_geographic_rollup`**

Edit `R/rollup.R`. Replace the existing function with:

```r
#' Aggregate spending across state/county/city layers for a place
#'
#' Wraps [cog_spending()], tags each row with its layer, and attaches a
#' human-readable `scope_note` documenting geographic-scope caveats (e.g.
#' "county totals include areas outside the listed city"). Useful for
#' "place portraits" that compare a city to the surrounding county and
#' containing state on one set of axes.
#'
#' When `per_capita = TRUE`, rows whose government has no observed
#' population in that year (`pop_source == "unavailable"`) are dropped from
#' the result. The dropped govids are recorded in
#' `provenance$rollup$excluded_govids`. This excludes special districts
#' (gov type 4) and school districts (gov type 5) from per-capita rollups
#' by design — see `vignette('population-denominators')`.
#'
#' @param govids Named list with any non-empty subset of elements named
#'   `state`, `county`, `city`. Each element is a character vector of
#'   `canonical_govid` values. At least one layer required.
#' @param category Single category name or character vector (passed through
#'   to [cog_spending()]).
#' @param years Integer vector of years.
#' @param per_capita If `TRUE`, per-capita uses each gov's own per-year
#'   population from `gov_population_yearly`. Govs with missing population
#'   are excluded from the result.
#' @param adjust_to_year Integer base year for CPI-U conversion, or `NULL`.
#' @return Tibble with columns `year`, `layer`, `canonical_govid`, `gov_name`,
#'   `spend_subtype`, `category`, `amt_nominal`, optional `amt_real` /
#'   `amt_per_capita_nominal` / `amt_per_capita_real`, optional `pop_source`,
#'   `codes_included`, `aggregate_fallback`, `scope_note`, `notes`. Carries a
#'   `provenance` attribute with `verb = "cog_geographic_rollup"`, `layers`,
#'   and `rollup$included_govids` / `rollup$excluded_govids`.
#' @export
cog_geographic_rollup <- function(govids, category, years,
                                  per_capita = FALSE, adjust_to_year = NULL) {
  call <- match.call()
  .validate_rollup_layers(govids)

  govids <- lapply(govids, .coerce_govid_input, arg = "govids[[layer]]")
  if (any(lengths(govids) == 0L)) {
    cli::cli_abort("Each layer in `govids` must be non-empty after coercion.")
  }
  layer_names <- names(govids)
  all_govids  <- unlist(govids, use.names = FALSE)
  layer_map   <- tibble::tibble(
    canonical_govid = all_govids,
    layer           = rep(layer_names, lengths(govids))
  )

  r <- cog_spending(all_govids, years, category, per_capita, adjust_to_year)
  r <- dplyr::left_join(r, layer_map, by = "canonical_govid",
                        relationship = "many-to-many")
  r$scope_note <- .rollup_scope_note(r$layer)

  excluded <- character(0)
  if (isTRUE(per_capita) && "pop_source" %in% names(r)) {
    drop <- r$pop_source == "unavailable"
    excluded <- unique(r$canonical_govid[drop])
    r <- r[!drop, , drop = FALSE]
  }
  included <- unique(r$canonical_govid)

  r <- .reorder_rollup_cols(r)

  prov <- attr(r, "provenance")
  prov$verb   <- "cog_geographic_rollup"
  prov$call   <- paste(deparse(call), collapse = " ")
  prov$layers <- layer_names
  prov$rollup <- list(
    included_govids = included,
    excluded_govids = excluded
  )
  attr(r, "provenance") <- prov

  r
}
```

`.validate_rollup_layers`, `.rollup_scope_note`, `.reorder_rollup_cols` are unchanged.

- [ ] **Step 2: Run tests**

```bash
Rscript -e 'devtools::test(filter = "rollup")'
```

Expected: ALL PASS.

- [ ] **Step 3: Commit**

```bash
git add R/rollup.R
git commit -m "feat(rollup): drop unavailable-pop rows + provenance audit

cog_geographic_rollup(per_capita = TRUE) now drops rows whose government
has no observed population for that year (pop_source == 'unavailable'),
matching the spec's exclusion rule. Records included/excluded govids in
provenance\$rollup."
```

---

## Task 10: Update provenance for new denominator metadata

**Files:**
- Modify: `R/provenance.R:54-74`
- Modify: `R/spending.R` `.verb_spendrev` to pass result with `pop_source` to `.build_provenance`
- Modify: `tests/testthat/test-spending.R` (append)

- [ ] **Step 1: Write failing test**

Append to `tests/testthat/test-spending.R`:

```r
test_that("provenance records per-year denominator metadata", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("101006006", years = 2019:2020,
                      category = "Police", per_capita = TRUE)
    pc <- attr(r, "provenance")$transformations$per_capita
    expect_true(pc$applied)
    expect_match(pc$denominator_source, "Census F-33", fixed = FALSE)
    expect_match(pc$denominator_source, "per-year", fixed = TRUE)
    expect_equal(pc$pop_source_counts$census_f33, nrow(r))
    expect_equal(pc$pop_source_counts$unavailable, 0L)
    expect_equal(length(pc$popyear_range), 2L)
  })
})
```

- [ ] **Step 2: Run to verify failure**

```bash
Rscript -e 'devtools::test(filter = "spending")'
```

Expected: FAIL — `pop_source_counts` is NULL, `denominator_source` still reads "ACS 2018-2022".

- [ ] **Step 3: Plumb popyear through to provenance**

The popyear range needs to come from `gov_population_yearly`. Two options: re-query inside `.build_provenance`, or have `.attach_per_capita` stash a `popyear_range` attribute on the result. Stash on the result is simpler and avoids a duplicate query.

Edit `.attach_per_capita` in `R/spending.R` so the SQL also pulls `popyear`, and after computing per-capita, drop the column but stash min/max as attributes:

Replace the SQL block + assignment:

```r
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
```

- [ ] **Step 4: Update `.build_provenance`**

Replace the `per_capita` block in `R/provenance.R`:

```r
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
```

- [ ] **Step 5: Strip `.popyear_range` attr after provenance is built**

In `.verb_spendrev` (`R/spending.R:42-80`), after the line `attr(result, "provenance") <- prov`, add:

```r
  attr(result, ".popyear_range") <- NULL
```

so the helper attribute does not leak into the public surface.

- [ ] **Step 6: Run tests**

```bash
Rscript -e 'devtools::test()'
```

Expected: ALL PASS across spending, rollup, peers, explain.

- [ ] **Step 7: Commit**

```bash
git add R/spending.R R/provenance.R tests/testthat/test-spending.R
git commit -m "feat(provenance): record per-year denominator metadata

Updates transformations\$per_capita with the new denominator_source string,
popyear_range, and pop_source_counts. .attach_per_capita stashes
popyear_range on the result; .verb_spendrev strips the helper attr after
provenance is built."
```

---

## Task 11: Render new provenance fields in `cog_explain()`

**Files:**
- Modify: `R/explain.R:69-82` (Transformations block)
- Modify: `tests/testthat/test-explain.R` (append)

- [ ] **Step 1: Write failing test**

Append to `tests/testthat/test-explain.R`:

```r
test_that("cog_explain prints denominator + popyear_range + counts", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("101006006", years = 2019:2020,
                      category = "Police", per_capita = TRUE)
    out <- capture.output(cog_explain(r))
    expect_true(any(grepl("Census F-33", out)))
    expect_true(any(grepl("popyear", out, ignore.case = TRUE)))
    expect_true(any(grepl("census_f33", out)))
  })
})
```

- [ ] **Step 2: Run to verify failure**

```bash
Rscript -e 'devtools::test(filter = "explain")'
```

Expected: FAIL.

- [ ] **Step 3: Update `.print_provenance`**

In `R/explain.R`, replace the `pc <- prov$transformations$per_capita` block with:

```r
  pc <- prov$transformations$per_capita
  if (isTRUE(pc$applied)) {
    cli::cli_text("Per-capita denominator: {pc$denominator_source}")
    if (length(pc$popyear_range) == 2L) {
      cli::cli_text(
        "  popyear range: {pc$popyear_range[1]}-{pc$popyear_range[2]}"
      )
    }
    if (!is.null(pc$pop_source_counts)) {
      cli::cli_text(
        "  pop_source counts: census_f33={pc$pop_source_counts$census_f33}, unavailable={pc$pop_source_counts$unavailable}"
      )
    }
  }
```

- [ ] **Step 4: Run tests**

```bash
Rscript -e 'devtools::test(filter = "explain")'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/explain.R tests/testthat/test-explain.R
git commit -m "feat(explain): render new per-capita provenance fields

cog_explain() now prints denominator_source, popyear_range, and
pop_source_counts under the Transformations section."
```

---

## Task 12: Population-denominators vignette

**Files:**
- Create: `vignettes/population-denominators.Rmd`
- Modify: `DESCRIPTION` (add `Suggests: knitr, rmarkdown` if missing)

- [ ] **Step 1: Verify vignette infrastructure**

```bash
grep -E "VignetteBuilder|knitr|rmarkdown" DESCRIPTION
ls vignettes/ 2>/dev/null
```

If no other vignettes exist or `knitr`/`rmarkdown` is missing from `Suggests`, add to DESCRIPTION:

```
Suggests:
    knitr,
    rmarkdown,
    testthat (>= 3.0.0),
    withr
VignetteBuilder: knitr
```

(Only add the lines that aren't already present.)

- [ ] **Step 2: Create the vignette**

Write `vignettes/population-denominators.Rmd`:

````markdown
---
title: "Population denominators"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{Population denominators}
  %\VignetteEngine{knitr::knitr}
  %\VignetteEncoding{UTF-8}
---

```{r setup, include = FALSE}
knitr::opts_chunk$set(eval = FALSE, collapse = TRUE, comment = "#>")
```

# Why per-year population matters

Per-capita finance numbers divide each year's spending or revenue by a population denominator. The choice of denominator is a research decision, not an implementation detail: a 24-year corpus paired with a single 5-year ACS estimate produces biased per-capita values whose magnitude scales with each government's population change.

`uscogdata` defaults to the **Census F-33 population value Census itself uses to compute its published per-capita tables.** That value is recorded on every COG row as `population`, with `popyear` indicating the vintage. For a city that grew from 200,000 to 300,000 between 2000 and 2023, this default reproduces the per-capita value Census published. A static ACS denominator would have understated 2000 per-capita by ~33%.

# The four population sources

| Source | What it is | Default in uscogdata? |
|---|---|---|
| Census F-33 `population` | Population value Census used on each COG row to compute its published per-capita tables. Almost always a Population Estimates Program (PEP) estimate; sometimes lagged a year for fiscal-year alignment, recorded in `popyear`. | **Yes — default for `cog_spending(per_capita = TRUE)` etc.** |
| PEP (raw) | Census Bureau's official annual intercensal estimates, distinct from F-33 because F-33 sometimes uses a lagged vintage. | No (not in corpus) |
| ACS 5-year | American Community Survey 5-year rolling average. Different methodology, has margin of error, only available 2005-2009 onward. | Used by `cog_find_peers()` historically; replaced in 0.1 by per-year F-33. Still available in `canonical_fips_xwalk.population_acs` for non-time-series uses. |
| Decennial count | Actual count, every 10 years. | No (not in corpus) |

The F-33 denominator is preferred because it's the same value Census uses internally — so `uscogdata` per-capita numbers reconcile with Census's own published tables.

# Coverage

F-33 `population` is observed for gov types 0–3 (state, county, city, township). Gov types 4 (special districts) and 5 (school districts) have `population` masked to NA in the F-33 schema. uscogdata returns:

- `pop_source = "census_f33"` and a numeric `amt_per_capita_*` for types 0–3.
- `pop_source = "unavailable"` and `NA` per-capita for types 4–5, with a corresponding entry in `notes`.

`cog_geographic_rollup(per_capita = TRUE)` excludes unavailable-pop rows from the result; the dropped govids are listed in `provenance\$rollup\$excluded_govids`.

# The popyear quirk

Census sometimes uses a population estimate from one year prior to the fiscal year being reported (e.g., FY2018 paired with a 2017 PEP estimate) so the denominator is available before the fiscal year closes. `popyear` records which vintage was paired; `cog_spending()` returns the popyear range in `provenance\$transformations\$per_capita\$popyear_range` rather than as a per-row column.

# Time-varying peer cohorts

`cog_find_peers(target, year = Y)` builds a cohort matched on each candidate's population at year `Y`. The cohort is fixed once chosen; `cog_peer_compare()` then runs that cohort across whatever `years` you ask for. To run a moving-window comparison, build cohorts year-by-year and stitch the results:

```r
years <- 2010:2023
out <- purrr::map_dfr(years, function(y) {
  peers <- cog_find_peers("231082082", year = y, max_peers = 10L)
  cog_peer_compare("231082082", peers,
                   category = "Police", years = y,
                   per_capita = TRUE)
})
```

Each row in `out` has `cohort_year == year`, so a faceted plot shows cohort drift directly.

# Future direction

`pop_source` is a column on the result, not a fixed value, so adding a new denominator (PEP from tidycensus, decennial counts, ACS time-series) is a join change rather than an API change. A future release may add `cog_spending(..., pop_source = "pep")` for users who need a single externally-audited series.
````

- [ ] **Step 3: Build vignettes locally to confirm**

```bash
Rscript -e 'devtools::build_vignettes()'
```

Expected: builds without error; HTML appears in `doc/`.

- [ ] **Step 4: Commit**

```bash
git add vignettes/population-denominators.Rmd DESCRIPTION
git commit -m "docs(vignette): population denominators rationale + usage

Explains the four population sources, why F-33 is the default, type-4/5
coverage gap, the popyear quirk, and how to build moving-window peer
cohorts manually."
```

---

## Task 13: Pipeline data dictionary entry

**Files:**
- Modify: `../cog_pipeline/docs/data_dictionary.md` (sibling repo)

This task touches a different git repo. The cog_pipeline repo lives at `../cog_pipeline/` relative to the uscogdata working directory.

- [ ] **Step 1: Locate the data dictionary**

```bash
ls ../cog_pipeline/docs/data_dictionary.md
```

If the file does not exist, create it; otherwise append to the appropriate column-reference section.

- [ ] **Step 2: Add the population block**

Append (or insert under any existing column reference) the following section:

```markdown
## `population` and `popyear`

`long.population` and `long.popyear` are population metadata columns from the F-33 fixed-width files. Census uses them to compute the per-capita tables in its own COG publications.

- **Source bytes:** `population` from cols 124-132 (older years) or cols 117-125 (modern format); `popyear` from cols 133-134 / 126-127. See `R/read_modern.R` for the exact mappings per fiscal-year layout.
- **Vintage:** `popyear` is a 2-digit year identifying which Population Estimates Program (PEP) value Census paired with that fiscal year. PEP estimates are sometimes lagged a year for fiscal-year alignment (e.g., FY2018 paired with 2017 PEP).
- **Coverage:** Populated for gov types 0–3 (state, county, city, township). Masked to NA for gov types 4 (special districts) and 5 (school districts) in `R/read_modern.R::.apply_phase_e_masking()`. Schools instead carry `enrollment` / `enrollyear`.
- **Relationship to PEP:** `population` is approximately the PEP estimate for `popyear` for that geography. It is *not* identical to a tidycensus `get_estimates()` pull because Census occasionally revises PEP retroactively while the F-33 value is frozen at publication.
- **Downstream use:** `uscogdata::cog_spending(per_capita = TRUE)` exposes this as the `census_f33` denominator via the `gov_population_yearly` view.
```

- [ ] **Step 3: Commit in cog_pipeline**

```bash
cd ../cog_pipeline
git add docs/data_dictionary.md
git commit -m "docs(data-dict): document long.population / long.popyear

Adds source byte ranges, vintage semantics, type-4/5 masking rule, and
downstream use by uscogdata's per-capita denominator."
cd ../uscogdata
```

---

## Task 14: NEWS.md entry

**Files:**
- Modify: `NEWS.md` (top of file, under or above the existing latest entry)

- [ ] **Step 1: Read current NEWS.md**

```bash
head -30 NEWS.md
```

- [ ] **Step 2: Add Unreleased entry**

Insert at the top of `NEWS.md` (above the most recent dated entry):

```markdown
# uscogdata (development version)

## Per-capita denominators now use per-year Census F-33 population

`cog_spending()` and `cog_revenue()` previously divided all years' amounts by a single ACS 2018-2022 estimate (`canonical_fips_xwalk.population_acs`), producing biased per-capita values for time-series analysis. They now divide by the F-33 `population` recorded on each gov-year via the new `gov_population_yearly` view. Result tibbles gain a `pop_source` column with values `"census_f33"` or `"unavailable"`. `notes` is updated to concatenate multiple notes with `"; "`.

## Peer cohorts can be set to a chosen year

`cog_find_peers()` adds a `year` argument (default: most recent year for which the target has an observed population in `gov_population_yearly`). The returned column previously named `population_acs` is now `population` and reflects the cohort year's vintage. The cohort year is attached to the returned tibble as `attr(x, "cohort_year")`.

`cog_peer_compare()` now stamps a `cohort_year` column on its result (read from the peers tibble's attribute) and records `cohort_year` plus `cohort_govids` in provenance. When the caller supplies a bare character vector instead of a `cog_find_peers()` result, `cohort_year` is `NA`.

## Rollups exclude govs missing population

`cog_geographic_rollup(per_capita = TRUE)` drops rows whose government has `pop_source == "unavailable"` and records the dropped govids in `provenance$rollup$excluded_govids`. This excludes special districts (type 4) and school districts (type 5) from per-capita rollups by design.

## New: vignette and provenance metadata

- New vignette `population-denominators` covers the four population sources, the type-4/5 coverage gap, the popyear quirk, and how to build moving-window peer cohorts manually.
- Provenance gains `transformations$per_capita$popyear_range` and `pop_source_counts`. `cog_explain()` renders both.
```

- [ ] **Step 3: Run the full test suite one more time**

```bash
Rscript -e 'devtools::test()'
```

Expected: ALL tests pass (181+ existing + ~12 new = ~193+).

- [ ] **Step 4: Commit**

```bash
git add NEWS.md
git commit -m "docs(news): per-year population denominators (unreleased)

Summarizes the per-capita and peer-cohort behavior changes for users
upgrading from earlier 0.1 snapshots."
```

---

## Task 15: Document refresh + final R CMD check

**Files:**
- Re-generate: `man/*.Rd` from updated roxygen
- Re-generate: `NAMESPACE` (no exports change, but document() will refresh)

- [ ] **Step 1: Run `devtools::document()`**

```bash
Rscript -e 'devtools::document()'
```

Expected: `man/cog_find_peers.Rd`, `man/cog_geographic_rollup.Rd`,
`man/cog_spending.Rd`, `man/cog_revenue.Rd`, `man/cog_explain.Rd` are
regenerated.

- [ ] **Step 2: Run R CMD check**

```bash
Rscript -e 'devtools::check(args = c("--no-manual", "--no-build-vignettes"))'
```

Expected: 0 ERRORs, 0 WARNINGs, 0 NOTEs (or only pre-existing acceptable notes).

- [ ] **Step 3: Commit doc regeneration**

```bash
git add man/ NAMESPACE
git commit -m "docs(roxygen): regenerate man pages for per-year population work"
```

- [ ] **Step 4: Push**

```bash
git push origin main
```

(Only when human review of the full series is complete and the engineer is authorized to push.)

---

## Verification checklist

After all tasks land, verify:

- [ ] `devtools::test()` reports 0 failures
- [ ] `devtools::check()` reports 0 ERRORs / 0 WARNINGs
- [ ] `cog_spending("101006006", 2019:2020, "Police", per_capita = TRUE)` returns different `amt_per_capita_nominal` for 2019 vs 2020 with the implied denominators matching `gov_population_yearly`
- [ ] `cog_find_peers("101006006")` returns a tibble with `population` (not `population_acs`) and `attr(x, "cohort_year") == 2020`
- [ ] `cog_geographic_rollup(per_capita = TRUE)` for a state+county+city set returns rows for each gov tagged by layer, with per-row per-year per-capita
- [ ] `cog_explain()` output mentions "Census F-33" and "popyear range"
- [ ] `vignette("population-denominators", package = "uscogdata")` opens
- [ ] cog_pipeline's `docs/data_dictionary.md` includes the population entry

## Out of scope (do not do)

- Adding PEP / ACS time-series / decennial denominators (architected for, not implemented)
- Adding a `per_pupil` denominator using `long.enrollment`
- Backfilling type-4/5 population from external sources
- Updating `cog_explorer/` callers — separate follow-up
- Bumping the package version
