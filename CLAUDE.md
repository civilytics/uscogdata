# CLAUDE.md — Agent Instructions for uscogdata

## Project Overview

R package providing a curated reader API for the Civilytics US Census of
Governments finance corpus. Reads Hive-partitioned parquet + `manifest.json`
published by `cog_pipeline` via DuckDB (local path or remote URL). This is a
standalone Gitea repo, sibling to `cog_explorer/cog_pipeline/`.

**Gitea remote:** `gitea.civilytics.org/Civilytics/uscogdata`  
**Full implementation plan:** `../cog_pipeline/docs/plan_phase_n_tasks.md` (Tasks 2.1–2.8 + Phase 3)  
**Reader contract spec:** `../cog_pipeline/docs/reader-specification.md`

## Architecture

### Data flow

```
USCOGDATA_URL (local path or https://) 
  → cog_open() fetches manifest.json, registers DuckDB views from inst/sql/
  → verbs query views via DBI
  → results carry provenance attr
```

### Key files

- `R/config.R` — `.cfg()`, `.resolve_url()`, `.uscogdata_env` (mutable state)
- `R/session.R` — `cog_open()`, `cog_close()`, `.ensure_session()`, `.coerce_govid_input()`
- `R/manifest.R` — `.fetch_or_cache_manifest()`, `.is_local_path()` (local paths bypass HTTP/cache)
- `R/views.R` — `.register_views()` (substitutes `{url}` into SQL files at `inst/sql/`)
- `inst/sql/` — 7 SQL view definitions: `long`, `spending_long`, `revenue_long`, `canonical_fips_xwalk`, `summary_categories`, `spending_annotated`, `revenue_annotated`
- `R/spending.R` / `R/revenue.R` — `cog_spending()` / `cog_revenue()` via shared `.verb_spendrev()`
- `R/rollup.R` — `cog_geographic_rollup()` (accepts named list of govids by layer)
- `R/peers.R` — `cog_find_peers()` + `cog_peer_compare()`
- `R/search.R` — `cog_gov_search()` (name pattern, state, type filters)
- `R/mirror.R` — `cog_mirror()` (local corpus copy via httr2 WebDAV)
- `R/explain.R` — `cog_explain()` (prints/returns provenance attr)
- `R/categories.R` — `cog_categories()` (queries `summary_categories` view)
- `R/adjust.R` — `.inflate()` helper using bundled CPIAUCSL in `sysdata.rda`
- `R/provenance.R` — `.build_provenance()` attached as attr to all verb results

### Corpus URL resolution

`USCOGDATA_URL` env var → `uscogdata.url` option → default placeholder in `config.R`.
Any value without `://` is treated as a local path by `.is_local_path()` and reads
`manifest.json` directly from disk (no HTTP, no TTL cache).

## Current State (2026-04-27)

**Version:** 0.1.0 (pre-release)  
**Branch:** `main`, commit `d65e9fe`  
**Tests:** 181 PASS / 0 FAIL / 0 SKIP  
**CI:** Gitea Actions green (`.gitea/workflows/ci.yml`)

### Completed (Tasks 2.1–2.7)

All 8 exported verbs implemented and tested:
`cog_spending`, `cog_revenue`, `cog_explain`, `cog_geographic_rollup`,
`cog_find_peers`, `cog_peer_compare`, `cog_gov_search`, `cog_mirror`,
plus `cog_categories`.

Bundled fixture corpus at `inst/extdata/fixture_corpus/` (3.6 MB, years
2019+2020, all 50 states). Tests run fully offline — no credentials needed.

### Remaining to v0.1 release

1. **Task 2.8 — Docs:** roxygen `@param`/`@return`/`@examples` on all exports;
   full `README.md`; `_pkgdown.yml`; `devtools::document()` + `pkgdown::build_site()`.
   Vignettes can be stubbed for v0.1.

2. **Phase 3 — cog_explorer bridge:** create
   `cog_explorer/examples/hello_world_uscogdata.Rmd` (installs from Gitea, runs
   `cog_spending()` against live Nextcloud corpus, renders a chart). Gate N14.

3. **Release gates:** run test suite against live corpus
   (`USCOGDATA_URL=<live-url> devtools::test()`), add
   `^inst/extdata/fixture_corpus$` to `.Rbuildignore`, tag `v0.1.0`, cut
   Gitea release.

## Testing

```r
devtools::test()          # uses bundled fixture, fully offline
testthat::test_local()    # same, used by CI
```

`tests/testthat/setup.R` sets `USCOGDATA_URL` to the bundled fixture automatically.
`helper-fixture.R` provides `skip_if_no_corpus()`, `fixture_corpus_path()`,
`with_fixture_corpus()`.

To run against the live corpus:
```r
Sys.setenv(USCOGDATA_URL = "<live-url-with-trailing-slash>")
devtools::test()
```

## Coding Conventions

- All verbs call `.ensure_session()` first, then query via `DBI::dbGetQuery()`
- Return value is always a `tbl_df` with a `provenance` attribute
- govid inputs always go through `.coerce_govid_input()` (accepts character or data frame)
- SQL lives in `inst/sql/` — never inline SQL strings in R files
- No arrow dependency — DuckDB reads parquet natively
- `withr` is a Suggests-only dep; only used in tests
