# uscogdata

Curated R reader for the Civilytics US Census of Governments finance corpus.

Provides unit-level financial profiles, geographic rollups, and peer comparisons
with auditable provenance and built-in cross-vintage correctness. Reads the
published corpus (Hive-partitioned parquet + manifest.json) directly from
Nextcloud via DuckDB httpfs — no local bulk downloads required.

## Status

Under active development (Phase 2 of the cog_pipeline project). See
`../cog_pipeline/docs/reader-specification.md` for the reader contract this
package implements.

## Installation

```r
# pak::pkg_install("gitea.civilytics.org/Civilytics/uscogdata")
```

## Configuration

- `USCOGDATA_URL` — corpus root URL (public Nextcloud share, trailing slash)
- `USCOGDATA_CACHE_DIR` — optional override for the manifest cache directory
- `USCOGDATA_MANIFEST_TTL_SECS` — optional manifest re-fetch TTL (default 3600)

## Direct vs Total spending

`cog_spending(..., expenditure_concept = c("direct", "total"))` controls
whose spending a result counts. `"direct"` (the default) is a government's
own current operations, capital outlay, and other direct spending. `"total"`
additionally adds in the intergovernmental legs — money it hands to other
governments to spend on its behalf — which is meaningful for describing one
government's own budget over time, but double-counts when summed across
governments (a state's payment to a county is the same dollar the county
reports as its own direct spending).

**Rule of thumb: any figure that spans more than one government uses
`direct`.** `cog_geographic_rollup()` and `cog_peer_compare()` enforce this
by refusing `expenditure_concept = "total"`. See
`vignette("total-spending", package = "uscogdata")` for the full
explanation with worked examples.

## Developer notes

### Testing

The package ships a bundled fixture corpus at `inst/extdata/fixture_corpus/` —
a 3.6 MB two-year slice (2019 + 2020) of the full corpus covering all 50
states. `tests/testthat/setup.R` automatically points `USCOGDATA_URL` at this
fixture, so the full test suite runs offline with no network dependency:

```r
devtools::test()   # uses bundled fixture, no credentials required
```

### Releasing against the live corpus

Before cutting a release, run the test suite against the published corpus to
catch any drift between the fixture and the real data:

```r
Sys.setenv(USCOGDATA_URL = "<published-corpus-url-with-trailing-slash>")
devtools::test()
```

When the live-corpus run is clean, strip the fixture from the built package by
adding this line to `.Rbuildignore`:

```
^inst/extdata/fixture_corpus$
```

The test suite is URL-agnostic — `setup.R` falls back to `USCOGDATA_URL` when
the bundled fixture is absent, so no test code changes are needed for the
release run or after stripping the fixture.
