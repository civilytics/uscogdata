# uscogdata 0.3.0 Public Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `uscogdata` installable and usable by a stranger — fix the corpus-unreachable defect, correct release metadata, and rewrite README and NEWS for a first public release.

**Architecture:** Two code changes fix the P0 (manifest-driven file enumeration replacing an HTTP-incompatible glob; a working public default URL). Everything else is metadata, packaging config, and documentation. Distribution mechanics (Gitea public, GitHub mirror, r-universe) are **out of scope for this plan** — they follow after checks are green.

**Tech Stack:** R (>= 4.1), DuckDB 1.5.5 via `duckdb`/`DBI`, `httr2`, `jsonlite`, `cli`, testthat 3e, pkgdown, roxygen2 7.3.3.

**Design spec:** `specs/2026-08-08-public-release-design.md`

## Global Constraints

- Package license is **MIT**. Copyright holder is **Civilytics Consulting LLC**.
- Author of record: **Jared E. Knowles**, `jared@civilytics.com`, ORCID **0000-0003-0005-9478**, roles `aut`/`cre`. Civilytics Consulting LLC is `cph`/`fnd`.
- Public corpus base URL (note the trailing slash, which `.resolve_url()` requires):
  `https://huggingface.co/datasets/civilytics/us-cog-finance/resolve/main/`
- Published corpus is **schema_version 7**; bundled fixture is **schema_version 6**. `.validate_schema()` accepts `c(4L, 5L, 6L, 7L)` and that list does not change in this plan.
- Corpus facts for documentation, measured 2026-08-08: **46,148,034 rows**, **56 partitions**, **190.6 MB**, government types **0–3**, **FY1967–FY2024** (no source data FY1968, FY1969).
- The bundled fixture at `inst/extdata/fixture_corpus/` **ships in the release**. Never add it to `.Rbuildignore`.
- Every amount column a verb returns is in **full US dollars**, already multiplied by 1000. Documentation must never tell a user to apply the $1,000s rule to verb output.
- Run the full suite with `devtools::test()` from the package root. It uses the bundled fixture and requires no network or credentials.

---

## File Structure

**Modified — code**
- `R/views.R` — gains `.long_files_sql()`; `.register_views()` substitutes a second token. This is the only file that knows how the `long` table's paths are built.
- `inst/sql/10-long.sql` — the one file containing a glob. Becomes token-driven.
- `R/config.R` — default corpus URL.
- `R/manifest.R` — `.check_url_configured()` guidance text only; the sentinel check itself is unchanged.

**Modified — metadata/packaging**
- `DESCRIPTION`, `LICENSE`, `.Rbuildignore`, `_pkgdown.yml`

**Created**
- `LICENSE.md`, `CONTRIBUTING.md`
- `tests/testthat/test-long-files.R` — unit tests for enumeration
- `tests/testthat/test-live-corpus.R` — network-gated integration test

**Rewritten**
- `README.md`, `NEWS.md`

**Deliberately untouched:** every verb file (`R/spending.R`, `R/revenue.R`, `R/balances.R`, `R/rollup.R`, `R/peers.R`, `R/search.R`), `R/mirror.R`, and all other `inst/sql/*.sql`. The enumeration fix is confined to view registration by design.

---

## Task 1: Manifest-driven partition enumeration

The P0 defect, part one. `inst/sql/10-long.sql` globs `{url}data/long/**/*.parquet`. DuckDB 1.5.5 refuses globs over generic HTTP, and `allow_asterisks_in_http_paths` does not help — it forwards the literal `**/*` as a filename and 404s, because HTTP exposes no directory listing. The manifest already enumerates every partition under `files$long_partitions[]`.

**Files:**
- Modify: `R/views.R` (add helper; `.register_views()` at the `gsub` line)
- Modify: `inst/sql/10-long.sql:3`
- Test: `tests/testthat/test-long-files.R` (create)

**Interfaces:**
- Consumes: `.sql_lit_chr(x)` from `R/spending.R:553` — quotes each element, escapes `'` by doubling, joins with `,` and **no space**. `%||%` from `R/manifest.R:158`.
- Produces: `.long_files_sql(url, manifest)` returning a single SQL string — either a bracketed list literal `['a','b']` or, on fallback, a single quoted glob `'…/**/*.parquet'`. Task 3 relies on this being the only place partition paths are constructed.

**Critical constraint:** `tests/testthat/test-views.R:322` calls `.register_views(con, url, manifest = list(schema_version = 4L))` — a manifest with **no `files` element at all**. The helper must not error on it. The glob fallback exists for exactly this case and for local paths, where globbing works fine.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-long-files.R`:

```r
test_that(".long_files_sql enumerates every partition the manifest lists", {
  manifest <- list(files = list(long_partitions = list(
    list(year = 2011L, path = "data/long/year=2011/part-0.parquet"),
    list(year = 2012L, path = "data/long/year=2012/part-0.parquet")
  )))
  expect_equal(
    uscogdata:::.long_files_sql("https://example.org/corpus/", manifest),
    paste0(
      "['https://example.org/corpus/data/long/year=2011/part-0.parquet',",
      "'https://example.org/corpus/data/long/year=2012/part-0.parquet']"
    )
  )
})

test_that(".long_files_sql falls back to the glob when no partition list is present", {
  # test-views.R registers views with a hand-built manifest that has no
  # `files` element. That must keep working: the glob is valid for the
  # local paths such a manifest is used with.
  expect_equal(
    uscogdata:::.long_files_sql("/tmp/corpus/", list(schema_version = 4L)),
    "'/tmp/corpus/data/long/**/*.parquet'"
  )
  expect_equal(
    uscogdata:::.long_files_sql("/tmp/corpus/", list(files = list(long_partitions = list()))),
    "'/tmp/corpus/data/long/**/*.parquet'"
  )
})

test_that("the enumerated list matches the bundled fixture's partition count", {
  skip_if_no_corpus()
  m <- jsonlite::fromJSON(
    file.path(fixture_corpus_path(), "manifest.json"), simplifyVector = FALSE
  )
  out <- uscogdata:::.long_files_sql(fixture_corpus_path(), m)
  expect_equal(
    lengths(regmatches(out, gregexpr("part-0\\.parquet", out))),
    length(m$files$long_partitions)
  )
})

test_that("registered `long` view reads through the enumerated list", {
  skip_if_no_corpus()
  with_fixture_corpus({
    con <- uscogdata:::.ensure_session()
    n <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM long")$n
    expect_gt(n, 0)
    yrs <- DBI::dbGetQuery(con, "SELECT DISTINCT year FROM long ORDER BY year")$year
    expect_true(all(c(2011, 2012, 2019, 2020) %in% yrs))
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "long-files")'`
Expected: FAIL — `could not find function ".long_files_sql"` on the first three; the fourth may pass already (it exercises the glob against a local fixture, which works).

- [ ] **Step 3: Add the helper to `R/views.R`**

Insert immediately above `#' Register DuckDB views from inst/sql/ SQL files`:

```r
#' Build the SQL path expression for the partitioned `long` table.
#'
#' DuckDB cannot expand a glob over generic HTTP: there is no directory
#' listing to expand against, and `allow_asterisks_in_http_paths` only
#' forwards the literal `**/*` as a filename, which 404s. Measured against
#' the published corpus on 2026-08-08, an explicit file list returns the
#' same 46,148,034 rows the (working) `hf://` glob does, and
#' `hive_partitioning = true` still recovers `year` from the paths.
#'
#' The manifest already enumerates every partition, so we build the list
#' from it. This is host-agnostic -- Nextcloud, HuggingFace and a local
#' fixture take the same path -- where an `hf://` URL would tie the reader
#' to one vendor's protocol and still need special-casing, since manifest
#' fetching goes through httr2, which cannot speak `hf://`.
#'
#' Falls back to the glob when the manifest carries no partition list: a
#' hand-built manifest in a test (see test-views.R) or a corpus predating
#' the field. Both are local, where globbing works.
#' @noRd
.long_files_sql <- function(url, manifest) {
  parts <- manifest$files$long_partitions %||% list()
  if (length(parts) == 0L) {
    return(.sql_lit_chr(paste0(url, "data/long/**/*.parquet")))
  }
  paths <- vapply(parts, function(p) as.character(p$path), character(1))
  paste0("[", .sql_lit_chr(paste0(url, paths)), "]")
}
```

- [ ] **Step 4: Substitute the new token in `.register_views()`**

In `R/views.R`, replace this line:

```r
    sql <- gsub("\\{url\\}", url, sql, fixed = FALSE)
```

with:

```r
    sql <- gsub("\\{long_files\\}", .long_files_sql(url, manifest), sql, fixed = FALSE)
    sql <- gsub("\\{url\\}", url, sql, fixed = FALSE)
```

Order matters: `{long_files}` expands to a string containing the url, so it must be substituted first or the `{url}` pass would have nothing to do and the token would survive.

- [ ] **Step 5: Change the SQL to use the token**

`inst/sql/10-long.sql` line 3 becomes:

```sql
FROM read_parquet({long_files}, hive_partitioning = true);
```

Note there are **no surrounding quotes** — `.long_files_sql()` returns its own quoting, whether a bracketed list or a single quoted glob.

- [ ] **Step 6: Run the new tests**

Run: `Rscript -e 'devtools::test(filter = "long-files")'`
Expected: PASS, all four.

- [ ] **Step 7: Run the full suite for regressions**

Run: `Rscript -e 'devtools::test()'`
Expected: PASS. Pay particular attention to `test-views.R` — it is the file that exercises `.register_views()` with a `files`-less manifest.

- [ ] **Step 8: Commit**

```bash
git add R/views.R inst/sql/10-long.sql tests/testthat/test-long-files.R
git commit -m "fix: enumerate long partitions from the manifest instead of globbing

DuckDB cannot expand a glob over generic HTTP -- no directory listing --
so every remote corpus read failed. Only local paths worked, which is how
the API and the test fixture run, so nothing caught it.

Measured against the published corpus: the explicit list returns the same
46,148,034 rows, with hive_partitioning still recovering year."
```

---

## Task 2: Ship a working default corpus URL

The P0 defect, part two. The default is the literal `REPLACE_WITH_SHARE_TOKEN` sentinel and no file in the repo supplies a real URL, so a new user has no path to a working session.

**Files:**
- Modify: `R/config.R:7`
- Modify: `R/manifest.R` (the `i =` guidance line in `.check_url_configured()`)
- Modify: `tests/testthat/test-manifest.R:11`, `:38`
- Test: `tests/testthat/test-config.R` (add cases)

**Interfaces:**
- Consumes: `.cfg("url")`, `.resolve_url()` from `R/config.R`.
- Produces: a `.uscogdata_defaults$url` that is a real, reachable, credential-free URL. Task 3's integration test depends on this being the default.

**Critical constraint:** `tests/testthat/test-manifest.R` hardcodes the placeholder at lines 11 and 38 and asserts `cog_open()` aborts with `uscogdata_url_not_configured`. Changing the default **breaks those two tests** and they must be updated in this task. The test at line 26 passes an explicit sentinel-bearing URL via env var — it keeps passing untouched, and it is what proves the sentinel guard still works.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-config.R`:

```r
test_that("the default corpus URL is real, not a placeholder", {
  withr::with_envvar(c(USCOGDATA_URL = NA), {
    withr::with_options(list(uscogdata.url = NULL), {
      url <- uscogdata:::.resolve_url()
      expect_false(grepl("REPLACE_WITH", url, fixed = TRUE))
      expect_match(url, "^https://", perl = TRUE)
      expect_match(url, "/$", perl = TRUE)
    })
  })
})

test_that("an explicitly-set sentinel URL still aborts", {
  # The guard must survive the default change: a user who half-edited a
  # copied config still gets the actionable error.
  withr::with_envvar(
    c(USCOGDATA_URL = "https://other.example/s/REPLACE_WITH_SHARE_TOKEN/x/"), {
      expect_error(
        uscogdata:::.check_url_configured(uscogdata:::.resolve_url()),
        class = "uscogdata_url_not_configured"
      )
    })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: FAIL on the first test — the resolved default still contains `REPLACE_WITH`.

- [ ] **Step 3: Change the default**

`R/config.R`, in `.uscogdata_defaults`:

```r
.uscogdata_defaults <- list(
  # Public HuggingFace mirror of the published corpus: CC-BY-4.0, no
  # credential, CDN-backed. Chosen as the default so `library(uscogdata)`
  # followed by a verb works with zero configuration. Trailing slash is
  # required -- every consumer concatenates onto this (see .resolve_url()).
  url               = "https://huggingface.co/datasets/civilytics/us-cog-finance/resolve/main/",
  cache_dir         = NULL,
  manifest_ttl_secs = 3600L
)
```

- [ ] **Step 4: Update the stale guidance line**

In `R/manifest.R`, inside `.check_url_configured()`, replace:

```r
      i = "For the live Civilytics corpus, request the Nextcloud share URL from the package maintainer."
```

with:

```r
      i = "The public corpus is the default; unset USCOGDATA_URL to use it, or point it at a local copy from {.code cog_mirror()}."
```

- [ ] **Step 5: Correct the two now-inaccurate test names**

Both affected tests in `tests/testthat/test-manifest.R` set `USCOGDATA_URL` **explicitly** via `withr::with_envvar` before calling `cog_open()`, so they keep passing unchanged. Only their wording becomes wrong — the sentinel URL is no longer the default.

Line 7, rename the test:

```r
test_that("cog_open aborts with actionable error when URL contains the sentinel", {
```

Lines 11 and 38, rename the variable and say why it is still here:

```r
  # No longer the package default (that is the public HF corpus). This is a
  # user who copied a config template and did not finish editing it.
  sentinel_url <- "https://cloud.civilytics.org/s/REPLACE_WITH_SHARE_TOKEN/download/"
```

Update the two `withr::with_envvar(c(USCOGDATA_URL = placeholder), ...)` call sites in those tests to use `sentinel_url`. No functional change — do not alter the assertions.

- [ ] **Step 6: Run the affected files**

Run: `Rscript -e 'devtools::test(filter = "config|manifest")'`
Expected: PASS.

- [ ] **Step 7: Run the full suite**

Run: `Rscript -e 'devtools::test()'`
Expected: PASS. `setup.R` points `USCOGDATA_URL` at the bundled fixture for the whole suite, so the default change should not affect any other file.

- [ ] **Step 8: Commit**

```bash
git add R/config.R R/manifest.R tests/testthat/test-config.R tests/testthat/test-manifest.R
git commit -m "feat: default to the public corpus so the package works unconfigured

The default was a REPLACE_WITH_SHARE_TOKEN sentinel and no file in the
repo supplied a working URL, so a new user had no path to a session. The
sentinel guard stays for half-edited configs."
```

---

## Task 3: Live-corpus integration test

Nothing in the suite exercises a remote corpus — that is why the P0 survived. This test is network-gated so it skips in offline CI but runs on demand and before release.

**Files:**
- Test: `tests/testthat/test-live-corpus.R` (create)

**Interfaces:**
- Consumes: `.long_files_sql()` (Task 1), the default URL (Task 2), and the public verbs `cog_gov_search()`, `cog_spending()`, `cog_explain()`.
- Produces: nothing consumed downstream.

- [ ] **Step 1: Write the test**

Create `tests/testthat/test-live-corpus.R`:

```r
# Network-gated. Set USCOGDATA_LIVE_TEST=true to run.
#
# This file exists because the P0 fixed in this release -- no remote corpus
# was readable at all -- survived precisely because every other test path
# used a LOCAL corpus (the bundled fixture) and so did the API in
# production. Nothing ever exercised the code the way a new user does.
skip_live <- function() {
  testthat::skip_if_not(
    identical(tolower(Sys.getenv("USCOGDATA_LIVE_TEST", "")), "true"),
    "live-corpus test: set USCOGDATA_LIVE_TEST=true to run"
  )
}

test_that("the package reads the public corpus with no configuration at all", {
  skip_live()
  withr::with_envvar(c(USCOGDATA_URL = NA, USCOGDATA_FIXTURE_URL = NA), {
    withr::with_options(list(uscogdata.url = NULL), {
      uscogdata:::cog_close()
      on.exit(uscogdata:::cog_close(), add = TRUE)

      g <- cog_gov_search(name = "Madison", state = "WI", type = 2)
      expect_gt(nrow(g), 0)

      s <- cog_spending(g$canonical_govid[1], years = 2022)
      expect_gt(nrow(s), 0)
      expect_true(all(c("amt_nominal", "year", "category") %in% names(s)))

      # Amounts are full dollars, already x1000. A city's total annual
      # spending is millions, not thousands -- this catches a regression
      # that reintroduced the double conversion.
      expect_gt(sum(s$amt_nominal, na.rm = TRUE), 1e6)

      p <- attr(s, "provenance")
      expect_true(isTRUE(p$transformations$units_conversion$applied))
      expect_equal(p$transformations$units_conversion$multiplier, 1000)
    })
  })
})

test_that("a full-history query spans the published range", {
  skip_live()
  withr::with_envvar(c(USCOGDATA_URL = NA, USCOGDATA_FIXTURE_URL = NA), {
    withr::with_options(list(uscogdata.url = NULL), {
      uscogdata:::cog_close()
      on.exit(uscogdata:::cog_close(), add = TRUE)

      g <- cog_gov_search(name = "Madison", state = "WI", type = 2)
      s <- cog_spending(g$canonical_govid[1])
      # The corpus publishes FY1967-FY2024. Any single government's span is
      # narrower, but a full-history query must cross more than one decade
      # -- if enumeration silently returned one partition, this fails.
      expect_gt(diff(range(s$year)), 10)
    })
  })
})
```

- [ ] **Step 2: Run it gated off (default) — it must skip, not fail**

Run: `Rscript -e 'devtools::test(filter = "live-corpus")'`
Expected: SKIP on both, with the message about `USCOGDATA_LIVE_TEST`.

- [ ] **Step 3: Run it live**

Run: `USCOGDATA_LIVE_TEST=true Rscript -e 'devtools::test(filter = "live-corpus")'`
Expected: PASS. This is the first time the package has ever read a remote corpus successfully. If it fails, Task 1 is incomplete — do not proceed.

- [ ] **Step 4: Record the measured verb latency**

Run and note the wall time, which the README needs (raw scans were 1.5 s / 2.8 s; real verbs do more work):

```bash
USCOGDATA_LIVE_TEST=true Rscript -e '
  Sys.unsetenv("USCOGDATA_URL")
  library(uscogdata)
  g <- cog_gov_search(name = "Madison", state = "WI", type = 2)
  print(system.time(cog_spending(g$canonical_govid[1], years = 2022)))
  print(system.time(cog_spending(g$canonical_govid[1])))
'
```

Carry these two numbers into Task 8. Do not reuse the raw-scan figures.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-live-corpus.R
git commit -m "test: exercise the public corpus end to end, unconfigured

The remote-read defect survived because every test path used a local
corpus. This is the only test that runs the package the way a new user
does."
```

---

## Task 4: DESCRIPTION metadata

**Files:**
- Modify: `DESCRIPTION`

**Interfaces:**
- Produces: `URL`/`BugReports` that Task 7 (`_pkgdown.yml`) and Task 8 (README) both reference; the `Authors@R` that `citation("uscogdata")` renders.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-config.R`:

```r
test_that("DESCRIPTION carries release metadata", {
  skip_if_no_source_tree("DESCRIPTION")
  d <- read.dcf(source_tree_path("DESCRIPTION"))
  fields <- colnames(d)

  expect_true(all(c("URL", "BugReports") %in% fields))
  expect_match(d[1, "Authors@R"], "Knowles", fixed = TRUE)
  expect_match(d[1, "Authors@R"], "0000-0003-0005-9478", fixed = TRUE)
  expect_match(d[1, "Authors@R"], "Civilytics Consulting LLC", fixed = TRUE)

  # The gate in .validate_schema() accepts up to 7 and the published corpus
  # IS 7; DESCRIPTION must not claim otherwise.
  expect_equal(as.integer(d[1, "MaxCorpusSchema"]), 7L)
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: FAIL — `URL`/`BugReports` absent, `MaxCorpusSchema` is 5.

- [ ] **Step 3: Edit DESCRIPTION**

Replace the `Authors@R` block:

```
Authors@R: c(
    person(c("Jared", "E."), "Knowles",
           email = "jared@civilytics.com",
           role = c("aut", "cre"),
           comment = c(ORCID = "0000-0003-0005-9478")),
    person("Civilytics Consulting LLC", role = c("cph", "fnd")))
```

The given-name vector `c("Jared", "E.")` with family name `"Knowles"` matches
`merTools` exactly. That structural match is what lets ORCID and r-universe
collate both packages as one person's work — `person("Jared", "E. Knowles")`
would render identically but put the middle initial in the family-name slot.

Add after `Description:`:

```
URL: https://github.com/civilytics/uscogdata, https://civilytics.r-universe.dev/uscogdata
BugReports: https://github.com/civilytics/uscogdata/issues
```

Change:

```
MaxCorpusSchema: 7
```

Bump the version — this release changes user-visible behaviour (remote reads
go from broken to working; the default URL from placeholder to live corpus),
which is a minor bump, not a patch:

```
Version: 0.3.0
```

- [ ] **Step 4: Verify the person object parses**

Run: `Rscript -e 'print(eval(parse(text = read.dcf("DESCRIPTION")[1, "Authors@R"])))'`
Expected: prints two entries — `Jared E. Knowles <jared@civilytics.com> [aut, cre] (ORCID: ...)` and `Civilytics Consulting LLC [cph, fnd]`. A parse error here means a malformed `person()` call.

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DESCRIPTION tests/testthat/test-config.R
git commit -m "chore: release metadata -- author of record, URLs, schema ceiling

Authors@R was an org with no human, so citation() and the r-universe
maintainer page had nothing to render. MaxCorpusSchema claimed 5 while the
code accepts 7 and the published corpus is 7."
```

---

## Task 5: License files

**Files:**
- Modify: `LICENSE`
- Create: `LICENSE.md`

- [ ] **Step 1: Generate both files**

Run: `Rscript -e 'usethis::use_mit_license("Civilytics Consulting LLC")'`

This rewrites `LICENSE` to the two-line stub with the corrected holder and creates `LICENSE.md` with the full MIT text. It may also add `^LICENSE\.md$` to `.Rbuildignore` — that is correct and already present.

- [ ] **Step 2: Verify**

Run: `Rscript -e 'cat(readLines("LICENSE"), sep = "\n")'`
Expected:
```
YEAR: 2026
COPYRIGHT HOLDER: Civilytics Consulting LLC
```

Run: `Rscript -e 'cat(length(readLines("LICENSE.md")), "lines\n")'`
Expected: a non-zero count (the full MIT text, ~21 lines).

- [ ] **Step 3: Confirm DESCRIPTION still declares the license correctly**

Run: `Rscript -e 'cat(read.dcf("DESCRIPTION")[1, "License"], "\n")'`
Expected: `MIT + file LICENSE`. If `usethis` changed it, that is fine — leave whatever it wrote.

- [ ] **Step 4: Commit**

```bash
git add LICENSE LICENSE.md DESCRIPTION .Rbuildignore
git commit -m "chore: add full MIT text, name the copyright holder properly

LICENSE held only the two-line stub and no LICENSE.md existed, so the
repo carried no license text for a human or for GitHub's detector."
```

---

## Task 6: Ship the vignettes

`.Rbuildignore` excludes `^vignettes$`, so an installed package has no vignettes at all — while README tells users to run `vignette("total-spending", package = "uscogdata")`. Both vignettes build offline: `total-spending.Rmd` points `USCOGDATA_URL` at the bundled fixture, `population-denominators.Rmd` is `eval = FALSE`.

**Files:**
- Modify: `.Rbuildignore`
- Test: `tests/testthat/test-config.R` (add)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-config.R`:

```r
test_that("vignettes are not excluded from the build", {
  skip_if_no_source_tree(".Rbuildignore")
  ignore <- readLines(source_tree_path(".Rbuildignore"), warn = FALSE)
  expect_false(any(grepl("^\\^vignettes\\$$", ignore)))
  # The fixture is what lets R CMD check run offline with no credentials on
  # r-universe and GitHub Actions. It must never be excluded.
  expect_false(any(grepl("fixture_corpus", ignore, fixed = TRUE)))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: FAIL on the first expectation.

- [ ] **Step 3: Remove the three lines**

Delete these lines from `.Rbuildignore`:

```
^vignettes$
^doc$
^Meta$
```

Leave every other line untouched — in particular `^_pkgdown\.yml$`, `^docs$`, `^data-raw$`, `^specs$`, `^plans$`, `^\.gitea$`, `^CLAUDE\.md$` are all correct exclusions.

- [ ] **Step 4: Build the tarball and confirm the vignettes are in it**

```bash
Rscript -e 'devtools::build(path = tempdir())'
```
Then list the tarball contents:
```bash
tar -tzf "$(ls -t $(Rscript -e 'cat(tempdir())')/uscogdata_*.tar.gz | head -1)" | grep -E 'vignettes|inst/doc'
```
Expected: both `.Rmd` files appear under `uscogdata/vignettes/`.

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .Rbuildignore tests/testthat/test-config.R
git commit -m "fix: ship the vignettes

.Rbuildignore excluded ^vignettes$, so vignette(\"total-spending\") failed
for every user -- while the README instructed them to run it. Both build
offline against the bundled fixture."
```

---

## Task 7: pkgdown reference index

`_pkgdown.yml` lists 6 of 14 exports. pkgdown errors on topics missing from the index, so the docs site does not build.

**Files:**
- Modify: `_pkgdown.yml`

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-config.R`:

```r
test_that("_pkgdown.yml indexes every exported topic", {
  skip_if_no_source_tree("_pkgdown.yml", "NAMESPACE")
  exports <- grep("^export\\(", readLines(source_tree_path("NAMESPACE"), warn = FALSE), value = TRUE)
  exports <- sub("^export\\((.*)\\)$", "\\1", exports)
  yml <- paste(readLines(source_tree_path("_pkgdown.yml"), warn = FALSE), collapse = "\n")
  missing <- exports[!vapply(exports, function(e) grepl(paste0("\\b", e, "\\b"), yml), logical(1))]
  expect_equal(missing, character(0))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: FAIL listing the eight missing: `cog_categories`, `cog_explain`, `cog_find_peers`, `cog_geographic_rollup`, `cog_manifest`, `cog_mirror`, `cog_peer_compare`, `cog_recipes`.

- [ ] **Step 3: Rewrite `_pkgdown.yml`**

```yaml
url: https://civilytics.r-universe.dev/uscogdata

template:
  bootstrap: 5

reference:
  - title: Financial data
    desc: Spending, revenue and balance-sheet holdings for one or more governments.
    contents:
      - cog_spending
      - cog_revenue
      - cog_balances
  - title: Search & basket
    desc: Resolve place names into canonical govids.
    contents:
      - cog_gov_search
      - cog_basket_resolution
      - cog_basket_unresolved
  - title: Comparison & aggregation
    desc: Peer cohorts and geographic rollups.
    contents:
      - cog_find_peers
      - cog_peer_compare
      - cog_geographic_rollup
  - title: Corpus metadata
    desc: What the corpus contains, where it came from, and how to hold a local copy.
    contents:
      - cog_categories
      - cog_recipes
      - cog_manifest
      - cog_explain
      - cog_mirror

articles:
  - title: Concepts
    navbar: ~
    contents:
      - total-spending
      - population-denominators
```

- [ ] **Step 4: Build the site**

Run: `Rscript -e 'pkgdown::build_site(preview = FALSE)'`
Expected: completes without error. Any "Topics missing from index" warning means an export was missed.

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add _pkgdown.yml tests/testthat/test-config.R
git commit -m "docs: index all 14 exports in pkgdown, set the site url

The reference index covered 6 of 14, so pkgdown errored on the missing
topics and the docs site did not build."
```

`docs/` is gitignored via `.Rbuildignore`/`.gitignore`; do not commit built output.

---

## Task 8: README rewrite

The current README addresses someone inside the repo tree: status reads "Under active development (Phase 2 of the cog_pipeline project)", it points at `../cog_pipeline/docs/reader-specification.md`, the install line is commented out, and developer/testing/release sections sit above anything a user needs.

**Files:**
- Rewrite: `README.md`

**Interfaces:**
- Consumes: `URL`/`BugReports` from Task 4, the default URL from Task 2, the measured latencies from Task 3 Step 4.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-config.R`:

```r
test_that("README is written for a stranger, not a repo insider", {
  skip_if_no_source_tree("README.md")
  r <- paste(readLines(source_tree_path("README.md"), warn = FALSE), collapse = "\n")

  # No paths that only resolve inside Jared's checkout.
  expect_false(grepl("../cog_pipeline", r, fixed = TRUE))
  # A real, uncommented install line.
  expect_match(r, "install.packages", fixed = TRUE)
  expect_false(grepl("# pak::pkg_install", r, fixed = TRUE))
  # The errata most likely to produce a plausible-looking wrong answer.
  expect_match(r, "full US dollars", fixed = TRUE)
  # The release-instructions section that conflicts with public CI is gone.
  expect_false(grepl("Rbuildignore", r, fixed = TRUE))
  # Both read paths documented.
  expect_match(r, "cog_mirror", fixed = TRUE)
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: FAIL.

- [ ] **Step 3: Rewrite README.md in this order**

Write these sections, in this sequence. Content requirements are exact; prose is yours.

1. **Title + one-paragraph what-it-is.** Curated R reader over the Civilytics US Census of Governments finance corpus. State the coverage: government types 0–3 (state, county, municipality, township), **FY1967–FY2024** (no source data FY1968, FY1969), **46,148,034 rows**, **190.6 MB**. Add the r-universe version badge.

2. **Install.**
   ````markdown
   ```r
   install.packages("uscogdata",
     repos = c("https://civilytics.r-universe.dev",
               "https://cloud.r-project.org"))
   ```
   Or from source:
   ```r
   pak::pkg_install("git::https://gitea.civilytics.org/Civilytics/uscogdata.git")
   ```
   ````

3. **Quickstart — no configuration step.** Verbatim:
   ````markdown
   ```r
   library(uscogdata)

   # Resolve a place name to a canonical government id
   madison <- cog_gov_search(name = "Madison", state = "WI", type = 2)

   # Full spending history, real dollars, per capita
   spend <- cog_spending(madison$canonical_govid[1])

   # Every result carries its own provenance
   cog_explain(spend)
   ```
   ````

4. **Two ways to read the corpus.** Remote (default, zero setup) vs `cog_mirror()` (190 MB once). Include the measured table — **use the verb latencies recorded in Task 3 Step 4, not the raw-scan figures**:

   | | Remote (default) | Mirrored |
   |---|---|---|
   | Setup | none | `cog_mirror()`, 190.6 MB once |
   | Disk | 0 MB — HTTP range requests | 190.6 MB |
   | Per-query | network round trip | local |
   | Right for | trying it out, teaching, one-off questions | repeated analysis, offline work, reproducibility |

   State plainly: the default reads from a public HuggingFace mirror, and **the escape hatch is one function call** — after `cog_mirror()`, no analysis touches an external service.

5. **Amounts are in full US dollars.** Keep the existing text nearly verbatim — it is correct and carefully argued. Keep the `attr(r, "provenance")$transformations$units_conversion` example and the "do not multiply again" warning.

6. **Concepts.** Condense the existing primary/direct/total and general/total revenue sections to ~1/3 their length, each ending with a pointer to `vignette("total-spending")`. Add a short **Reporting coverage** paragraph: the Census is a complete census only in years ending in 2 and 7; every other year is a sample; `provenance$coverage` reports `n_units_reporting` per year, and `coverage = "census"` / `"consistent"` control the mode.

7. **How to cite.** `citation("uscogdata")` for the package; corpus is CC-BY-4.0, cite *Civilytics Consulting, US Census of Governments finance corpus*.

8. **Contributing.** Two sentences plus a link to `CONTRIBUTING.md` (Task 10).

**Delete outright:** the "Status" block, the `../cog_pipeline/...` reference, the entire "Developer notes / Testing / Releasing against the live corpus" section (it moves to `CONTRIBUTING.md`, minus the fixture-stripping advice, which is wrong and must not be carried over).

- [ ] **Step 4: Run the quickstart verbatim in a clean session**

```bash
Rscript -e '
  Sys.unsetenv("USCOGDATA_URL")
  devtools::load_all(".", quiet = TRUE)
  madison <- cog_gov_search(name = "Madison", state = "WI", type = 2)
  spend <- cog_spending(madison$canonical_govid[1])
  cat("rows:", nrow(spend), "years:", paste(range(spend$year), collapse = "-"), "\n")
  cog_explain(spend)
'
```
Expected: runs clean with no configuration. If it errors, the README is wrong — fix the README, not the test.

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "config")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add README.md tests/testthat/test-config.R
git commit -m "docs: rewrite README for a stranger

Reordered around a new user -- what it is, install, a quickstart that runs
with no configuration, then the dollars warning and the concepts. Drops
the sibling-repo path, the commented-out install line, and the
fixture-stripping release advice that conflicts with public CI."
```

---

## Task 9: NEWS.md rewrite

The current NEWS is a pre-release churn log spanning the package's entire development (2026-04-23 to 2026-08-04, 140 commits), describing changes relative to states no user has seen. To a newcomer it reads as instability.

**Files:**
- Rewrite: `NEWS.md`
- Modify: `README.md` and roxygen blocks receiving migrated content

- [ ] **Step 1: Migrate the load-bearing content first**

Before deleting anything, move each of these to its documentation home. Verify each lands before proceeding:

| Content in current NEWS | Destination |
|---|---|
| Coverage disclosure — census vs sample years, the 597-vs-112 Wisconsin example, `coverage` modes | README §6 (Task 8) **and** `@details` in `R/rollup.R`'s roxygen for `cog_geographic_rollup()` |
| `complete = TRUE` — the `reported` / `census_zero` / `not_reported` table | `@details` in `R/spending.R` and `R/revenue.R` roxygen |
| Series breaks and `corpus_break_refs` | `@details` in `R/provenance.R`'s `cog_explain()` roxygen |
| Per-year F-33 population denominators | already in `vignette("population-denominators")` — verify, do not duplicate |

Run `Rscript -e 'devtools::document()'` after editing roxygen.

- [ ] **Step 2: Restructure NEWS.md**

Three edits, in this order:

1. **Prepend** the `0.3.0` section below.
2. **Keep** the existing `# uscogdata 0.2.0` section verbatim — it is a real
   changelog (`"All Categories"`, the coverage-signposting fix, the
   `n_units_reporting` documentation) and users deserve it.
3. **Delete** the entire `# uscogdata 0.1.0 (development)` section and
   everything under it. That is pre-release churn; it stays in git.

The new top section:

```markdown
# uscogdata 0.3.0

First public release.

`uscogdata` provides curated R verbs over the Civilytics US Census of
Governments finance corpus: unit-level financial profiles, geographic
rollups, and peer comparisons, with auditable provenance on every result.

## What it covers

Government types 0–3 (state, county, municipality, township), FY1967–FY2024
(no source data for FY1968 or FY1969) — 46,148,034 rows across 56 fiscal
years. The corpus is published under CC-BY-4.0 and reads directly over
HTTPS, or locally after `cog_mirror()`.

## The verbs

`cog_spending()`, `cog_revenue()` and `cog_balances()` for flows and
holdings; `cog_gov_search()` to resolve place names (including basket mode
for many at once); `cog_find_peers()` and `cog_peer_compare()` for cohorts;
`cog_geographic_rollup()` for aggregates; `cog_categories()`,
`cog_recipes()`, `cog_manifest()` and `cog_explain()` for metadata and
provenance; `cog_mirror()` for a local copy.

## Four things to know before your first query

* **Amounts are in full US dollars.** The raw Census files report thousands;
  the verbs multiply by 1000 on the way out. Do not multiply again.
* **Multi-government aggregates disclose their coverage.** The Census is a
  complete census only in years ending in 2 and 7. Every result carries
  `provenance$coverage` with per-year `n_units_reporting`.
* **Absence means two different things.** Before FY2012 an absent cell means
  Census published $0; from FY2012 it means not reported.
  `complete = TRUE` labels which.
* **Series breaks reach you unasked.** Catalogued breaks intersecting your
  query appear in provenance and in `cog_explain()`.

## Known limits

* Special districts (type 4) and school districts (type 5) are out of scope.
* Per-capita rollups exclude governments with no F-33 population.
* Employee-retirement (`X`) codes stop at FY2016, when those systems moved
  to the Annual Survey of Public Pensions.
```

- [ ] **Step 3: Verify no orphaned content**

Run: `git show HEAD:NEWS.md > /tmp/news-old.md && wc -l /tmp/news-old.md NEWS.md`

Read `/tmp/news-old.md` once more and confirm every substantive claim from the **deleted `0.1.0 (development)` section** either appears in the new `0.3.0` section, landed somewhere in Step 1, or is genuinely pre-release churn (version bumps, fixture regenerations, internal refactors).

Then confirm the `0.2.0` section survived intact:

```bash
diff <(git show HEAD:NEWS.md | sed -n '/^# uscogdata 0.2.0/,/^# uscogdata 0.1.0/p' | head -n -1) \
     <(sed -n '/^# uscogdata 0.2.0/,$p' NEWS.md)
```
Expected: no output. Any diff means the `0.2.0` changelog was damaged — restore it.

- [ ] **Step 4: Run the full suite**

Run: `Rscript -e 'devtools::test()'`
Expected: PASS — `devtools::document()` in Step 1 regenerated `man/`, so this catches a malformed roxygen block.

- [ ] **Step 5: Commit**

```bash
git add NEWS.md README.md R/ man/
git commit -m "docs: recast NEWS around the first public release

The changelog described changes relative to states no user ever saw, which
reads as instability to someone deciding whether to depend on this. The
load-bearing caveats move into README and roxygen, where they belong; the
pre-release history stays in git."
```

---

## Task 10: CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`
- Modify: `.Rbuildignore`

- [ ] **Step 1: Write CONTRIBUTING.md**

It must contain, in this order:

1. **Canonical source note.** Development happens on `gitea.civilytics.org/Civilytics/uscogdata`; `github.com/civilytics/uscogdata` is a mirror that accepts issues and pull requests.

2. **What happens to a GitHub PR.** Verbatim explanation: it is fetched and landed on the canonical repo, then closes itself as merged when the mirror syncs — because the maintainer merges with `--no-ff`, preserving the contributor's commits and SHAs. Say plainly that a PR closing without a "Merged by" click is normal and not a rejection.

3. **Running the tests.**
   ````markdown
   ```r
   devtools::test()   # uses the bundled fixture; no network, no credentials
   ```
   ````
   Note that `tests/testthat/setup.R` points `USCOGDATA_URL` at
   `inst/extdata/fixture_corpus/` automatically.

4. **Testing against the live corpus.**
   ````markdown
   ```r
   USCOGDATA_LIVE_TEST=true devtools::test(filter = "live-corpus")
   ```
   ````
   Explain why it exists: every other test path uses a local corpus, which is
   how the remote-read defect fixed for 0.3.0 went unnoticed.

5. **Do not exclude the fixture from the build.** State the reason — it is what lets `R CMD check` pass on r-universe and GitHub Actions with no credentials.

6. **Release checklist**, moved from README: run the suite against both the fixture and the live corpus, `pkgdown::build_site()`, `R CMD check --as-cran`, tag, then update the r-universe registry pin.

**Do not carry over** the README's instruction to add `^inst/extdata/fixture_corpus$` to `.Rbuildignore`. It is wrong.

- [ ] **Step 2: Exclude it from the build**

Add to `.Rbuildignore`:

```
^CONTRIBUTING\.md$
```

- [ ] **Step 3: Verify the build is clean**

Run: `Rscript -e 'devtools::check(document = FALSE, args = "--no-manual")'`
Expected: 0 errors, 0 warnings. Notes about package size (the 15 MB fixture) are expected and acceptable — this package is not going to CRAN.

- [ ] **Step 4: Commit**

```bash
git add CONTRIBUTING.md .Rbuildignore
git commit -m "docs: add CONTRIBUTING with the canonical-on-Gitea PR flow

Moves developer and release instructions out of the README, minus the
fixture-stripping advice, which would break the vignette and leave public
CI unable to check without credentials."
```

---

## Final verification

Run before declaring the release ready. Every one of these must pass.

- [ ] **1. Full suite, offline, no credentials**
  `Rscript -e 'devtools::test()'` — the property public CI depends on.

- [ ] **2. Live corpus**
  `USCOGDATA_LIVE_TEST=true Rscript -e 'devtools::test()'`

- [ ] **3. `R CMD check --as-cran`**
  `Rscript -e 'devtools::check(args = "--as-cran")'` — 0 errors, 0 warnings.

- [ ] **4. pkgdown**
  `Rscript -e 'pkgdown::build_site(preview = FALSE)'`

- [ ] **5. Vignettes resolve from an installed copy**
  ```bash
  Rscript -e 'devtools::install(build_vignettes = TRUE, quiet = TRUE)'
  Rscript -e 'v <- vignette("total-spending", package = "uscogdata"); stopifnot(nzchar(v$File)); cat("OK\n")'
  ```

- [ ] **6. Cold-start check.** On a machine (or container) that has never had this package: install it, then run the README quickstart **verbatim with no environment variables set**.
  ```bash
  docker run --rm -v "$PWD":/pkg rocker/r-ver:4.4 bash -c '
    apt-get update -qq && apt-get install -y -qq libcurl4-openssl-dev libssl-dev >/dev/null
    Rscript -e "install.packages(c(\"pak\"), repos=\"https://cloud.r-project.org\")" \
      -e "pak::pkg_install(\"local::/pkg\")" \
      -e "library(uscogdata); m <- cog_gov_search(name=\"Madison\", state=\"WI\", type=2); s <- cog_spending(m\$canonical_govid[1]); cat(\"rows:\", nrow(s), \"\n\")"
  '
  ```
  **This is the only check that catches the P0 class of fault**, and its absence is why the fault survived. Do not skip it.

- [ ] **7. Verb latency re-measured** against the live corpus, and the README table updated if the numbers moved from what Task 3 Step 4 recorded.

## Out of scope for this plan

Flipping the Gitea repo public, `gitleaks`, the GitHub mirror and its Actions matrix, the Gitea push workflow, the r-universe registry, and tagging `v0.3.0`. Those follow after this plan's final verification is green — r-universe publishes check results on registration, so registering before checks pass means a red badge on day one. Corrections intake and announcement posts are deferred by decision (see the spec).
