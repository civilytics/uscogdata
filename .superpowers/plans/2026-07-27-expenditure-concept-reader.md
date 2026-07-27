# `expenditure_concept` in uscogdata — Implementation Plan (Repo 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `expenditure_concept = c("direct","total")` to `cog_spending()`, so a
user can ask for Census "Total" (Direct + intergovernmental) for a single
government — and cannot accidentally get it inside the cross-government verbs,
where summing Total double-counts intergovernmental transfers.

**Architecture:** The pipeline now publishes 66 intergovernmental (`M`/`L`) codes
in `summary_categories.parquet` under `spend_subtype = "intergovernmental"`
(merged as pipeline PR #59). `"direct"` keeps today's behavior exactly — the
existing `spending_annotated{,_harmonized}` views. `"total"` adds a second leg,
a new `ig_annotated{,_harmonized}` view, UNION'd in. The IG leg deliberately does
**not** reuse the Direct leg's `NOT is_aggregate` filter, because in the legacy
era the IG dollars live almost entirely on aggregate-flagged rows.

**Tech Stack:** R, DuckDB, testthat (3rd ed), roxygen2, `cli`.

## Global Constraints

- **Repo root:** `/home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata`. Always `cd` there in the same command as any git or R invocation. It is NESTED inside the `cog_explorer` git repo, so a bare `git` command can answer from the WRONG repo — confirm with `git rev-parse --show-toplevel` before believing any alarming git result.
- **Branch:** `feat/expenditure-concept` (already created off `main` @ `e581e73`).
- **Interpreter:** `/usr/bin/Rscript`, absolute paths. Conda shadows system R and lacks arrow/duckdb; IDE "package not installed" diagnostics are NOISE.
- **Commits:** `git -c commit.gpgsign=false commit` — a plain commit fails on a GPG "signing failed: Timeout".
- **Measured baseline on `main` (2026-07-27):** `FAIL 0 | WARN 0 | SKIP 0 | PASS 467`. (The earlier handoff's "471 with PR #8 / 463 without" figures are both wrong; 467 is measured.)
- **Tests are offline.** `tests/testthat/setup.R` points `USCOGDATA_URL` at the bundled fixture. Never write a test that requires the live corpus or a network fetch.
- **Do NOT merge the PR.** One PR per repo, stop for owner review.
- **`expenditure_concept` is spending-only.** Do NOT add it to `cog_revenue()` — the Direct/Total distinction is an expenditure concept and the parameter name says so. Revenue's intergovernmental codes (`B`/`C`/`D`) are already categorized by source and are a different axis.
- **Ruling reference:** `../cog_pipeline/docs/superpowers/specs/2026-07-25-total-spending-semantics-design.md` (rulings R1–R4).

## The two facts this design rests on (both measured against the published corpus)

**1. Aggregate IG rows carry NO `harmonized_code`.** Harmonized space is
leaf-only by construction:

| prefix | is_aggregate | harmonized_code NULL | rows | Σ amt |
|---|---|---|---:|---:|
| M | TRUE | **yes** | 2,918,024 | 6,434,679,266 |
| L | TRUE | **yes** | 2,188,518 | 307,079,345 |
| L | FALSE | yes (`L21`,`L24`) | 1,380,245 | 516,301 |

So the IG leg **cannot** go through `harmonized_code` alone — it would drop
almost all legacy IG. It joins on `COALESCE(harmonized_code, item_code)`, which
keeps the one real IG collapse rule (`M38 → M36`, SB012 — year-disjoint, 1967–2011
vs 2012+) while never dropping an aggregate row.

**2. Aggregate IG codes are year-disjoint from their components, so ignoring
`is_aggregate` cannot double-count.** Measured per year:

| year | `M47` | `M94` | `M89`(agg) | `M91-93` | `L89`(agg) | `L91-93` | `M05`(agg) | `M04` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2010 | 6408 | 0 | 6408 | 0 | 6408 | 0 | 6408 | 0 |
| 2011 | 6422 | 0 | 6422 | 0 | 6422 | 0 | 6422 | 0 |
| 2012 | 0 | 224 | 0 | 329 | 0 | 86 | 0 | 598 |
| 2023 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 35 |

Every aggregate/component pair is perfectly disjoint — the same argument the
pipeline used to let recipe joins skip the filter
(`cog_pipeline/docs/phase_r_harmonization_review.md` § 0.2). The **only** row that
must be excluded is `L--`, the IG-to-state family total (Σ 248,812,372), which
genuinely does roll up the `L-NN` codes.

**What the rule is worth:** Σ IG by era —

| era | rule (`NOT LIKE '%--'`) | naive `NOT is_aggregate` | visible under naive |
|---|---:|---:|---:|
| legacy (≤2011) | 9,259,744,623 | 2,766,798,384 | **29.9%** |
| modern (2012+) | 3,648,584,806 | 3,648,584,806 | 100% |

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `inst/extdata/fixture_corpus/` | Offline test corpus | **Regenerate** (Task 1) — currently 194 category rows, 0 IG |
| `inst/sql/24-ig_long.sql` | IG rows, raw item_code | **Create** |
| `inst/sql/25-ig_long_harmonized.sql` | IG rows, COALESCE'd code | **Create** |
| `inst/sql/44-ig_annotated.sql` | IG + xwalk + categories | **Create** |
| `inst/sql/45-ig_annotated_harmonized.sql` | same, harmonized leg | **Create** |
| `R/views.R` | Registers `inst/sql/` files | **Verify** — likely globs, may need no change |
| `R/spending.R` | `cog_spending()`, `.verb_spendrev()`, `.build_verb_sql()` | **Modify** — new arg, UNION leg, drop `"K"` |
| `R/rollup.R` | `cog_geographic_rollup()` | **Modify** — arg + hard error |
| `R/peers.R` | `cog_peer_compare()` | **Modify** — arg + hard error |
| `R/provenance.R` | `.build_provenance()` | **Modify** — record the concept |
| `R/suggestions.R` | `.build_suggestions()` | **Modify** — name the IG counterpart recipe |
| `inst/schemas/provenance-v1.json` | Provenance contract | **Modify** — document the field |
| `tests/testthat/test-expenditure-concept.R` | The feature's tests | **Create** |
| `README.md`, `vignettes/total-spending.Rmd` | The two archetype questions | **Modify / Create** |

---

### Task 1: Regenerate the fixture corpus

Everything downstream tests against the fixture, and today's fixture has **194**
category rows and **zero** `M`/`L` codes — so no IG test can pass until this
lands. `data-raw/regenerate_fixture_corpus.R` is the maintained, scripted job for
exactly this.

**Files:**
- Modify: `inst/extdata/fixture_corpus/**` (regenerated, not hand-edited)
- Test: existing suite (this task must not change any assertion's meaning)

**Interfaces:**
- Consumes: the merged pipeline publish tree at
  `/home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/cog_pipeline/_targets/publish_cache`.
- Produces: a fixture whose `data/summary_categories.parquet` has **260** rows
  including **66** with `spend_subtype = "intergovernmental"` (34 `M`, 32 `L`),
  and whose `docs/` copies carry the amended `Total = Direct + M + L` text.

- [ ] **Step 1: Record the pre-regeneration state**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'p <- arrow::read_parquet("inst/extdata/fixture_corpus/data/summary_categories.parquet"); cat("BEFORE rows:", nrow(p), " IG:", sum(grepl("^[ML]", p$item_code)), "\n")' && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); r <- as.data.frame(testthat::test_local(reporter="silent")); cat(sprintf("BEFORE suite: PASS %d FAIL %d SKIP %d\n", sum(r$passed), sum(r$failed), sum(r$skipped)))'
```

Expected: `BEFORE rows: 194  IG: 0`, and `PASS 467 FAIL 0 SKIP 0`.

- [ ] **Step 2: Regenerate**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript data-raw/regenerate_fixture_corpus.R \
  /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/cog_pipeline/_targets/publish_cache
```

- [ ] **Step 3: Verify the fixture picked up the IG rows**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e '
p <- arrow::read_parquet("inst/extdata/fixture_corpus/data/summary_categories.parquet")
cat("AFTER rows:", nrow(p), "\n"); print(table(p$spend_subtype, useNA="ifany"))
cat("M:", sum(startsWith(p$item_code,"M")), " L:", sum(startsWith(p$item_code,"L")), "\n")
stopifnot(nrow(p)==260L, sum(p$spend_subtype %in% "intergovernmental")==66L)
cat("FIXTURE HAS IG ROWS\n")'
```

Expected: 260 rows; `capital 70 / intergovernmental 66 / operations 37 / NA 87`; M 34, L 32.

- [ ] **Step 4: Run the full suite and adjudicate every change**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); r <- as.data.frame(testthat::test_local(reporter="silent")); cat(sprintf("AFTER suite: PASS %d FAIL %d SKIP %d\n", sum(r$passed), sum(r$failed), sum(r$skipped))); bad <- r[r$failed>0|r$error, c("file","test")]; if(nrow(bad)) print(bad) else cat("NO FAILURES\n")'
```

**Expected: still PASS 467, FAIL 0.** The IG rows are inert until Task 3 — no
existing view selects `M`/`L` prefixes, so nothing should move.

**If any test fails, STOP and report rather than editing the assertion.** A
failure here means the fixture regeneration changed something beyond the
category table (e.g. a year partition or the manifest), and that needs
adjudicating against the pipeline change, exactly as `e813ffd` and PR #7 were
handled. Do not re-baseline a pinned value to make it pass.

- [ ] **Step 5: Commit**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
git add inst/extdata/fixture_corpus && \
git -c commit.gpgsign=false commit -m "chore: regenerate fixture corpus with the intergovernmental category rows

Picks up pipeline PR #59: summary_categories now carries 66 M/L rows under
spend_subtype = intergovernmental (194 -> 260 rows). Inert until the
expenditure_concept views land; suite unchanged at PASS 467."
```

---

### Task 2: Drop the inert `"K"` prefix

`flow_prefixes = c("E","F","G","K")` includes `K`, which matches **zero** rows
corpus-wide — audited pipeline-side (`docs/phase_r_harmonization_review.md` § 6:
*"Every raw FinEstDAT 2012–2023 contains zero K-prefix rows … Absence in the
corpus = absence in the product."*). Removing it changes no number.

**Files:**
- Modify: `R/spending.R:58` (`flow_prefixes`), `inst/sql/20-spending_long.sql`, `inst/sql/22-spending_long_harmonized.sql`
- Test: `tests/testthat/test-expenditure-concept.R` (create)

**Interfaces:**
- Produces: `cog_spending()`'s Direct leg selects prefixes `E`/`F`/`G` only.
  Every existing result is numerically unchanged.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-expenditure-concept.R`:

```r
test_that("the corpus contains no K-prefix rows, so the Direct leg omits K", {
  con <- .ensure_session()
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM long WHERE LEFT(item_code, 1) = 'K'")$n
  expect_equal(n, 0)

  sql_files <- c("20-spending_long.sql", "22-spending_long_harmonized.sql")
  for (f in sql_files) {
    txt <- paste(readLines(system.file("sql", f, package = "uscogdata")),
                 collapse = " ")
    expect_false(grepl("'K'", txt, fixed = TRUE),
                 label = paste(f, "must not reference the inert K prefix"))
  }
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); testthat::test_file("tests/testthat/test-expenditure-concept.R")'
```

Expected: the `COUNT(*)` expectation PASSES (K really is absent) and the two
`expect_false` expectations FAIL (the SQL still says `'K'`).

- [ ] **Step 3: Remove `K` from all three places**

`R/spending.R:58` — `flow_prefixes = c("E", "F", "G"),`

`inst/sql/20-spending_long.sql` — `WHERE LEFT(item_code, 1) IN ('E', 'F', 'G')`

`inst/sql/22-spending_long_harmonized.sql` — `AND LEFT(harmonized_code, 1) IN ('E', 'F', 'G')`

- [ ] **Step 4: Verify green and numerically inert**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); r <- as.data.frame(testthat::test_local(reporter="silent")); cat(sprintf("PASS %d FAIL %d SKIP %d\n", sum(r$passed), sum(r$failed), sum(r$skipped)))'
```

Expected: FAIL 0, and PASS = 467 + the new expectations. Any *changed* number in
a pre-existing test would mean `K` was not inert — stop and report.

- [ ] **Step 5: Commit**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
git add R/spending.R inst/sql/20-spending_long.sql inst/sql/22-spending_long_harmonized.sql tests/testthat/test-expenditure-concept.R && \
git -c commit.gpgsign=false commit -m "fix: drop the inert K prefix from the spending flow prefixes

K matches zero rows corpus-wide (audited pipeline-side). Numerically inert;
removed so the code stops implying a prefix the data never had."
```

---

### Task 3: `expenditure_concept` in `cog_spending()`

**Files:**
- Create: `inst/sql/24-ig_long.sql`, `inst/sql/25-ig_long_harmonized.sql`, `inst/sql/44-ig_annotated.sql`, `inst/sql/45-ig_annotated_harmonized.sql`
- Modify: `R/spending.R` (`cog_spending()`, `.verb_spendrev()`, `.build_verb_sql()`, `.select_view()`)
- Verify: `R/views.R` registers the new files
- Test: `tests/testthat/test-expenditure-concept.R`

**Interfaces:**
- Consumes: Task 1's fixture, Task 2's prefix list.
- Produces: `cog_spending(govid, years, category = NULL, per_capita = FALSE,
  adjust_to_year = NULL, basis = c("harmonized","raw"), recipe = NULL,
  expenditure_concept = c("direct","total"))`. With `"total"`, results gain rows
  whose `spend_subtype` is `"intergovernmental"`; `"direct"` is byte-for-byte
  today's behavior. Later tasks call it with `expenditure_concept` passed through.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-expenditure-concept.R`:

```r
test_that("expenditure_concept defaults to direct and preserves today's numbers", {
  gov <- "010000226085"                      # Alabama state government
  base <- cog_spending(gov, years = 2019, category = "Police")
  expl <- cog_spending(gov, years = 2019, category = "Police",
                       expenditure_concept = "direct")
  expect_equal(base$amt_nominal, expl$amt_nominal)
  expect_false("intergovernmental" %in% base$spend_subtype)
})

test_that("expenditure_concept = 'total' adds an intergovernmental subtype", {
  gov <- "010000226085"
  d <- cog_spending(gov, years = 2019, category = "Police",
                    expenditure_concept = "direct")
  t <- cog_spending(gov, years = 2019, category = "Police",
                    expenditure_concept = "total")
  expect_true("intergovernmental" %in% t$spend_subtype)
  # Direct rows are untouched; Total only ever ADDS.
  dt <- t[t$spend_subtype != "intergovernmental", ]
  expect_equal(sort(dt$amt_nominal), sort(d$amt_nominal))
  expect_gt(sum(t$amt_nominal), sum(d$amt_nominal))
})

test_that("legacy-era Total does not collapse to Direct (the is_aggregate trap)", {
  # In the wide era the IG dollars live almost entirely on aggregate-flagged
  # rows. A Total leg that inherited the Direct leg's NOT is_aggregate filter
  # would silently return Total == Direct here.
  gov <- "010000226085"
  d <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "direct")
  t <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total")
  expect_true("intergovernmental" %in% t$spend_subtype)
  ig <- sum(t$amt_nominal[t$spend_subtype == "intergovernmental"])
  expect_gt(ig, 0)
  expect_gt(sum(t$amt_nominal), sum(d$amt_nominal))
})

test_that("the IG leg never includes the L-- family total", {
  con <- .ensure_session()
  codes <- DBI::dbGetQuery(con,
    "SELECT DISTINCT item_code FROM ig_long")$item_code
  expect_false(any(grepl("--$", codes)))
  expect_true(all(substr(codes, 1, 1) %in% c("M", "L")))
})

test_that("expenditure_concept rejects unknown values", {
  expect_error(
    cog_spending("010000226085", years = 2019, expenditure_concept = "gross"),
    class = "rlang_error"
  )
})

test_that("total composes with basis = 'raw' and basis = 'harmonized'", {
  gov <- "010000226085"
  h <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total", basis = "harmonized")
  r <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total", basis = "raw")
  ig_h <- sum(h$amt_nominal[h$spend_subtype == "intergovernmental"])
  ig_r <- sum(r$amt_nominal[r$spend_subtype == "intergovernmental"])
  # The only IG harmonization rule is M38 -> M36 (year-disjoint), so the IG
  # total must agree between bases even though the code labels may differ.
  expect_equal(ig_h, ig_r)
})
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); testthat::test_file("tests/testthat/test-expenditure-concept.R")'
```

Expected: failures on `unused argument (expenditure_concept = ...)` and on the
missing `ig_long` view.

- [ ] **Step 3: Create the four SQL views**

`inst/sql/24-ig_long.sql`:

```sql
-- Intergovernmental expenditure rows (M = to local govts, L = to state govts).
--
-- Deliberately does NOT filter `NOT is_aggregate`, unlike spending_long. In the
-- wide era (<= FY2011) the IG families M05/M12/M47/M89/L47/L89 are published
-- ONLY as aggregate-flagged rows -- filtering them would hide ~70% of legacy IG
-- dollars and make Total silently collapse to Direct. This is safe because the
-- aggregate codes and their modern leaf components are strictly year-disjoint
-- (M47 ends 2011 / M94 starts 2012; M89 is aggregate only <= 2011 and a leaf
-- from 2012 alongside M91-93), so no row is ever counted twice. Same argument
-- the pipeline's recipe joins use.
--
-- `L--` IS excluded: it is the IG-to-state FAMILY TOTAL and genuinely rolls up
-- the L-NN codes, so including it would double-count.
CREATE OR REPLACE VIEW ig_long AS
SELECT *
FROM long
WHERE LEFT(item_code, 1) IN ('M', 'L')
  AND item_code NOT LIKE '%--';
```

`inst/sql/25-ig_long_harmonized.sql`:

```sql
-- Harmonized-basis IG rows. Uses COALESCE(harmonized_code, item_code) rather
-- than harmonized_code alone: aggregate rows carry NO harmonized_code by
-- construction (harmonized space is leaf-only), so a plain
-- `harmonized_code IS NOT NULL` filter would drop every legacy IG aggregate --
-- 6.4e9 of M and 3.1e8 of L in corpus units. COALESCE keeps the one real IG
-- collapse rule (M38 -> M36, SB012, year-disjoint 1967-2011 vs 2012+) while
-- never dropping a row.
CREATE OR REPLACE VIEW ig_long_harmonized AS
SELECT * REPLACE (COALESCE(harmonized_code, item_code) AS item_code)
FROM long
WHERE LEFT(item_code, 1) IN ('M', 'L')
  AND item_code NOT LIKE '%--';
```

`inst/sql/44-ig_annotated.sql`:

```sql
CREATE OR REPLACE VIEW ig_annotated AS
SELECT
  s.*,
  x.gov_name       AS xwalk_gov_name,
  x.govs_type,
  x.type_label,
  x.fips_state     AS xwalk_fips_state,
  x.fips_county    AS xwalk_fips_county,
  x.fips_place,
  x.population_acs,
  c.category,
  c.category_type,
  c.spend_subtype
FROM ig_long s
LEFT JOIN canonical_fips_xwalk x USING (canonical_govid)
LEFT JOIN summary_categories   c USING (item_code);
```

`inst/sql/45-ig_annotated_harmonized.sql`: identical, but `FROM ig_long_harmonized s`
and `CREATE OR REPLACE VIEW ig_annotated_harmonized AS`.

- [ ] **Step 4: Register the harmonized views against the schema guard**

`.register_views()` (`R/views.R:25-35`) globs `inst/sql/*.sql` and executes them
in **sorted filename order**, so the four new files register automatically — the
numbering above is chosen so `ig_long` (24/25) precedes `ig_annotated` (44/45),
which in turn follows `canonical_fips_xwalk` (30) and `summary_categories` (31).

But there is a guard at `R/views.R:30`: any file listed in
`.harmonization_view_files` is **skipped** when `schema_version < 5`. The two new
harmonized views read `harmonized_code`, which does not exist on a pre-v5 corpus,
so they MUST be added to that vector (`R/views.R:13-21`) or `cog_open()` will
abort against an older corpus:

```r
.harmonization_view_files <- c(
  "22-spending_long_harmonized.sql",
  "23-revenue_long_harmonized.sql",
  "25-ig_long_harmonized.sql",
  "33-harmonization_map.sql",
  "34-harmonization_recipes.sql",
  "35-series_breaks_pq.sql",
  "42-spending_annotated_harmonized.sql",
  "43-revenue_annotated_harmonized.sql",
  "45-ig_annotated_harmonized.sql"
)
```

Note the asymmetry that follows: on a pre-v5 corpus `ig_annotated_harmonized`
does not exist, so `.select_ig_view()` must resolve to the raw `ig_annotated`
whenever the *resolved* basis is `"raw"` — which the existing `.resolve_basis()`
already guarantees for pre-v5 corpora. Pass `resolved$basis`, never the
user's raw `basis` argument, exactly as `.select_view()` does.

Verify registration:

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); con <- .ensure_session(); print(DBI::dbGetQuery(con, "SELECT COUNT(*) n, COUNT(DISTINCT item_code) codes FROM ig_long"))'
```

Expected: a nonzero row count and 66 distinct codes (the fixture ships the full
metadata tables, but only the fixture's years of `long`, so `n` will be smaller
than the full corpus — the **codes** figure is the one that matters and may be
below 66 if a code is absent from the fixture's years; report what you see).

- [ ] **Step 5: Wire the argument through**

In `R/spending.R`, add the parameter to `cog_spending()` (roxygen `@param` too):

```r
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
```

In `.verb_spendrev()`, add `expenditure_concept = c("direct","total")` to the
signature, resolve it with `expenditure_concept <- match.arg(expenditure_concept)`
next to the existing `basis` handling, and pass an IG view into the SQL builder
only for the non-recipe path:

```r
    view <- .select_view(view_base, resolved$basis)
    ig_view <- if (identical(expenditure_concept, "total")) {
      .select_ig_view(resolved$basis)
    } else {
      NULL
    }
    sql <- .build_verb_sql(view, subtype_col, govid, years, category, ig_view)
```

Add the helper beside `.select_view()`:

```r
#' @noRd
.select_ig_view <- function(basis) {
  if (identical(basis, "harmonized")) "ig_annotated_harmonized" else "ig_annotated"
}
```

Change `.build_verb_sql()` to take `ig_view = NULL` and union it in. Replace the
`FROM %2$s` clause with a source expression built once:

```r
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
  ...
```

and substitute `source_expr` where the format string previously took `view`.

**Recipe interaction:** a `recipe` query bypasses the basis views entirely, so it
also bypasses the IG leg. If both `recipe` and `expenditure_concept = "total"`
are supplied, abort — the recipe already defines its own component set:

```r
  if (!is.null(recipe) && identical(expenditure_concept, "total")) {
    cli::cli_abort(c(
      "`recipe` and `expenditure_concept = \"total\"` are mutually exclusive.",
      i = "A recipe defines its own component codes; pass one or the other.",
      i = "For a recipe's intergovernmental counterpart, use the matching IG recipe (e.g. `corrections_ig_local_combined`)."
    ), class = "uscogdata_recipe_concept_conflict")
  }
```

Add a test for that abort alongside the others.

- [ ] **Step 6: Run to green**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); r <- as.data.frame(testthat::test_local(reporter="silent")); cat(sprintf("PASS %d FAIL %d SKIP %d\n", sum(r$passed), sum(r$failed), sum(r$skipped)))'
```

Expected: FAIL 0. Every pre-existing test must still pass unchanged — `"direct"`
is the default and must not move a single number.

- [ ] **Step 7: Commit**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
git add inst/sql R/spending.R R/views.R tests/testthat/test-expenditure-concept.R && \
git -c commit.gpgsign=false commit -m "feat: expenditure_concept = direct|total in cog_spending()

total adds an intergovernmental leg (M = to local, L = to state) as a UNION ALL
over new ig_annotated views. The IG leg deliberately skips NOT is_aggregate --
legacy IG lives almost entirely on aggregate rows, and the aggregate codes are
year-disjoint from their modern leaf components, so nothing double-counts.
L-- (the IG-to-state family total) is excluded. direct is the default and is
numerically unchanged."
```

---

### Task 4: Hard error in the cross-government verbs

Owner ruling R1: `expenditure_concept = "total"` must **error** in
`cog_geographic_rollup()` and `cog_peer_compare()`, and the message must tell the
user to use `direct` for cross-government work **and explain why**.

Note the honest justification, which differs per verb and should not be
overstated in the message: `cog_geographic_rollup()` does not itself sum — it
returns per-government rows tagged `state`/`county`/`city` and the user sums
them, which is exactly where hierarchical double-counting bites.
`cog_peer_compare()` emits quantile summary rows over same-type peers. The owner
ruled error for both (2026-07-27) to keep one rule across both repos.

**Files:**
- Modify: `R/rollup.R` (`cog_geographic_rollup()`), `R/peers.R` (`cog_peer_compare()`)
- Test: `tests/testthat/test-expenditure-concept.R`

**Interfaces:**
- Consumes: Task 3's `cog_spending()`.
- Produces: both verbs accept `expenditure_concept = c("direct","total")` and
  abort with condition class `uscogdata_concept_not_aggregatable` when `"total"`.

- [ ] **Step 1: Write the failing tests**

```r
test_that("cog_geographic_rollup refuses expenditure_concept = 'total'", {
  expect_error(
    cog_geographic_rollup(
      govids = list(state = "010000226085"),
      category = "Police", years = 2019,
      expenditure_concept = "total"
    ),
    class = "uscogdata_concept_not_aggregatable"
  )
})

test_that("cog_peer_compare refuses expenditure_concept = 'total'", {
  expect_error(
    cog_peer_compare(
      target_govid = "010000226085", peers = "010000226085",
      category = "Police", years = 2019,
      expenditure_concept = "total"
    ),
    class = "uscogdata_concept_not_aggregatable"
  )
})

test_that("the refusal message names the fix and the reason", {
  err <- tryCatch(
    cog_geographic_rollup(govids = list(state = "010000226085"),
                          category = "Police", years = 2019,
                          expenditure_concept = "total"),
    condition = function(e) e
  )
  msg <- paste(conditionMessage(err), collapse = " ")
  expect_match(msg, "direct")
  expect_match(msg, "double-count|double count")
})

test_that("both cross-government verbs still accept the direct default", {
  expect_no_error(
    cog_geographic_rollup(govids = list(state = "010000226085"),
                          category = "Police", years = 2019)
  )
})
```

- [ ] **Step 2: Run to verify they fail**

Expected: `unused argument (expenditure_concept = "total")` from both verbs.

- [ ] **Step 3: Implement the guard**

Add a shared helper in `R/spending.R`:

```r
#' @noRd
.abort_concept_not_aggregatable <- function(verb) {
  cli::cli_abort(c(
    "{.code expenditure_concept = \"total\"} cannot be used in {.fn {verb}}.",
    "*" = "Use {.code expenditure_concept = \"direct\"} (the default) for any \\
           comparison or sum that spans more than one government.",
    "i" = "Why: Census \"Total\" is a government's own Direct spending PLUS the \\
           money it hands to other governments. The receiving government reports \\
           that same dollar again as its own Direct when it actually spends it, \\
           so combining Total across governments counts intergovernmental \\
           transfers twice.",
    "i" = "For one government's own Total, use \\
           {.code cog_spending(expenditure_concept = \"total\")}."
  ), class = "uscogdata_concept_not_aggregatable")
}
```

In `cog_geographic_rollup()`, add `expenditure_concept = c("direct", "total")` to
the signature and, as the first statement after `call <- match.call()`:

```r
  expenditure_concept <- match.arg(expenditure_concept)
  if (identical(expenditure_concept, "total")) {
    .abort_concept_not_aggregatable("cog_geographic_rollup")
  }
```

Do the same in `cog_peer_compare()` with its own verb name. Add roxygen
`@param expenditure_concept` to both, stating that only `"direct"` is accepted
and why.

- [ ] **Step 4: Run to green**

Expected: FAIL 0 across the suite.

- [ ] **Step 5: Commit**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
git add R/rollup.R R/peers.R R/spending.R tests/testthat/test-expenditure-concept.R && \
git -c commit.gpgsign=false commit -m "feat: refuse expenditure_concept = total in the cross-government verbs

Owner ruling R1. Combining Census Total across governments counts
intergovernmental transfers twice, and these results land in Tableau where a
warning would be invisible -- so this is a hard error whose message names the
fix and the reason."
```

---

### Task 5: Provenance records the concept

**Files:**
- Modify: `R/provenance.R` (`.build_provenance()`), `R/spending.R` (pass it through), `inst/schemas/provenance-v1.json`
- Test: `tests/testthat/test-expenditure-concept.R`

**Interfaces:**
- Produces: every `cog_spending()` result's provenance carries
  `expenditure_concept` (always populated, never implicit), and an
  `expenditure_concept_note` naming the year-scoped IG assembly when `"total"`.

- [ ] **Step 1: Write the failing test**

```r
test_that("provenance always records the expenditure concept", {
  d <- cog_spending("010000226085", years = 2019, category = "Police")
  t <- cog_spending("010000226085", years = 2019, category = "Police",
                    expenditure_concept = "total")
  expect_equal(attr(d, "provenance")$expenditure_concept, "direct")
  expect_equal(attr(t, "provenance")$expenditure_concept, "total")
  # The note explains the non-obvious part: how legacy IG was assembled.
  expect_true(nzchar(attr(t, "provenance")$expenditure_concept_note))
  expect_true(is.na(attr(d, "provenance")$expenditure_concept_note) ||
              !nzchar(attr(d, "provenance")$expenditure_concept_note))
})

test_that("the provenance schema documents expenditure_concept", {
  sch <- jsonlite::fromJSON(
    system.file("schemas", "provenance-v1.json", package = "uscogdata"),
    simplifyVector = FALSE
  )
  expect_true("expenditure_concept" %in% names(sch$properties))
})
```

- [ ] **Step 2: Run to verify it fails** (fields are `NULL`; schema key absent).

- [ ] **Step 3: Implement**

Add `expenditure_concept = "direct"` and `expenditure_concept_note = NA_character_`
parameters to `.build_provenance()`, place them in the returned list next to
`basis`/`basis_note`, and pass them from `.verb_spendrev()`. The note when
`"total"`:

```
"Total = Direct + intergovernmental (M to local govts + L to state govts). Legacy-era IG is assembled from aggregate-flagged rows, which are year-disjoint from their modern leaf components; the L-- family total is excluded."
```

Add to `inst/schemas/provenance-v1.json`'s `properties`:

```json
    "expenditure_concept": {
      "type": "string",
      "enum": ["direct", "total"],
      "description": "Which spending concept produced this result. 'direct' is the government's own E/F/G spending; 'total' adds its intergovernmental payments (M to local governments, L to state governments). Only 'direct' is valid for results combined across governments."
    },
    "expenditure_concept_note": {
      "type": ["string", "null"],
      "description": "How the intergovernmental leg was assembled; null for 'direct'."
    }
```

- [ ] **Step 4: Run to green.** Expected FAIL 0.

- [ ] **Step 5: Commit**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
git add R/provenance.R R/spending.R inst/schemas/provenance-v1.json tests/testthat/test-expenditure-concept.R && \
git -c commit.gpgsign=false commit -m "feat: record expenditure_concept in provenance and its JSON schema

Always populated, never implicit, so a downstream artifact says which concept
produced it. cog-api passes provenance through verbatim."
```

---

### Task 6: Signposting — surface the IG recipe counterpart

uscogdata #6 item 4: *"when a user filters aggregate codes, the coverage/recipe
machinery should mention the concept choice where relevant."*

The concrete case: `.build_suggestions()` already fires when a category returns
no rows for some requested years and names the recipe that fills the gap (e.g.
`corrections_combined`). Several of those families have an **intergovernmental
counterpart recipe** — `corrections_ig_local_combined`, `ige_local_m47_wide`,
`ige_local_m89_wide`, `ige_state_l47_wide`, `ige_state_l89_wide`. A user who
took the Direct suggestion has no way to discover the IG one.

Scope this narrowly: only extend an **already-firing** suggestion. Do NOT add a
new trigger that fires on healthy queries — a message on every call is noise,
and the vignette is where the concept choice is taught.

**Files:**
- Modify: `R/suggestions.R` (`.build_suggestions()` / its message formatter)
- Test: `tests/testthat/test-expenditure-concept.R`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: when a suggestion fires for a recipe that has an IG counterpart in
  `harmonization_recipes`, the suggestion entry gains an `ig_recipe_id` field and
  the emitted message names it.

- [ ] **Step 1: Write the failing test**

```r
test_that("a firing suggestion names the intergovernmental counterpart recipe", {
  # Corrections has no legacy leaf rows, so the coverage-gap suggestion fires;
  # corrections_ig_local_combined is its IG counterpart.
  r <- suppressMessages(
    cog_spending("010000226085", years = c(2005, 2011), category = "Corrections")
  )
  sugg <- attr(r, "provenance")$suggestions
  expect_gt(length(sugg), 0L)
  ids <- vapply(sugg, function(s) s$recipe_id %||% "", character(1))
  expect_true("corrections_combined" %in% ids)
  ig <- unlist(lapply(sugg, function(s) s$ig_recipe_id))
  expect_true("corrections_ig_local_combined" %in% ig)
})

test_that("no suggestion fires for a healthy query", {
  r <- cog_spending("010000226085", years = 2019, category = "Police")
  expect_length(attr(r, "provenance")$suggestions, 0L)
})
```

- [ ] **Step 2: Run to verify the first fails** (no `ig_recipe_id` field) **and the
second passes** (pinning that we do not add a new trigger).

- [ ] **Step 3: Implement**

In `R/suggestions.R`, after the existing suggestion list is built, look up an IG
counterpart per suggested recipe. Derive it by matching on the recipe's function
suffix within `harmonization_recipes`, restricted to component codes whose first
letter is `M` or `L`. Attach as `ig_recipe_id` (`NULL` when there is none) and
append one clause to the emitted message, e.g.:

```
• corrections_combined (1967-2023): re-run with recipe = 'corrections_combined'
  intergovernmental counterpart: recipe = 'corrections_ig_local_combined'
```

- [ ] **Step 4: Run to green.** Expected FAIL 0 across the suite.

- [ ] **Step 5: Commit**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
git add R/suggestions.R tests/testthat/test-expenditure-concept.R && \
git -c commit.gpgsign=false commit -m "feat: name the intergovernmental counterpart in firing recipe suggestions

Closes uscogdata #6 item 4. Only extends suggestions that already fire -- a
concept hint on every healthy call would be noise."
```

---

### Task 7: README and the two-archetype vignette

**Files:**
- Create: `vignettes/total-spending.Rmd`
- Modify: `README.md`, `_pkgdown.yml` (if it enumerates vignettes)
- Test: none (prose), but the vignette must knit

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: docs anchored on the two archetype questions with worked code.

- [ ] **Step 1: Write the vignette**

Create `vignettes/total-spending.Rmd` with standard front matter
(`%\VignetteIndexEntry{Total spending: Direct, Total, and when each is right}`,
`%\VignetteEngine{knitr::rmarkdown}`). It must lead with the two archetype
questions and answer each with runnable code:

1. **Single-government trend** — *"total spending in my county, 2017 vs today"*.
   Show `cog_spending(..., expenditure_concept = "total")`, and note that either
   concept is valid here as long as it is applied consistently across years.
2. **Cross-government rollup** — *"all the counties in my state, ten years ago
   vs today, vs the neighbouring state"*. Show `cog_geographic_rollup()` with
   the default `direct`, then show the error from passing `"total"` and explain
   why it exists.

Include the mechanism in plain language — a state gives a county $10M for roads;
it is in the state's `M44` and again in the county's `E44`/`F44`; summing Total
counts it twice, so the rollup would report $20M of road spending for $10M of
road work.

State the composition rules explicitly: `expenditure_concept` (whose spending
counts) is orthogonal to `basis` (which vintage of code space); `"total"` is
mutually exclusive with `recipe`.

- [ ] **Step 2: Knit it**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); rmarkdown::render("vignettes/total-spending.Rmd", quiet = TRUE)' && echo KNIT_OK
```

Expected: `KNIT_OK`. Delete the rendered `.html` afterwards if it is not
gitignored — do not commit build output.

- [ ] **Step 3: Update the README**

Add a short "Direct vs Total spending" section pointing at the vignette, with
the one-line rule: **any figure that spans more than one government uses
`direct`.**

- [ ] **Step 4: Full suite + `R CMD check`-level sanity**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
/usr/bin/Rscript -e 'suppressMessages(pkgload::load_all(".", quiet=TRUE)); r <- as.data.frame(testthat::test_local(reporter="silent")); cat(sprintf("PASS %d FAIL %d SKIP %d\n", sum(r$passed), sum(r$failed), sum(r$skipped)))' && \
/usr/bin/Rscript -e 'devtools::document()' && git diff --stat man/ NAMESPACE
```

Expected: FAIL 0; `man/` regenerated for the changed roxygen blocks.

- [ ] **Step 5: Commit and open the PR**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/cog_explorer/uscogdata && \
git add -A && \
git -c commit.gpgsign=false commit -m "docs: total-spending vignette + README section on Direct vs Total" && \
git push -u origin feat/expenditure-concept
```

Then open the PR against `main` with `tea`, closing uscogdata #6. **Stop for
owner review; do not merge.**

---

## Deliberately out of scope

- **`J` prefix** (`J19`/`J67`/`J68`/`J85`, direct assistance/subsidies) — needs
  pipeline category rows first. Tracked as pipeline #58.
- **Public Welfare understatement / signposting** — uscogdata #9.
- **`cog_revenue()`** — `expenditure_concept` is an expenditure concept; revenue's
  IG codes are a different axis.
- **Repo 3 (`cog-api` #3)** — separate plan after this merges: same parameter name
  and default, HTTP 400 on aggregating endpoints, provenance passthrough, OpenAPI
  docs led by the two archetypes, then publish + `docker restart cog-api`.
