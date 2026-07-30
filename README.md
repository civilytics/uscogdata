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

## Amounts are in full US dollars

Every amount column this package returns — `amt_nominal`, `amt_real`,
`amt_per_capita_nominal`, `amt_per_capita_real` — is in **full US dollars**.

The raw Census source files report **thousands of dollars**, and the corpus's
own `amt` column preserves that. The verbs multiply by 1000 on the way out, so
you never have to. The conversion is recorded in every result:

```r
r <- cog_spending("552025209777", 2020L)
attr(r, "provenance")$transformations$units_conversion
#> $applied TRUE  $source_unit "$1,000s (raw Census)"  $target_unit "$USD"  $multiplier 1000
```

**Do not multiply again.** If you have read elsewhere that COG amounts are in
`$1,000s` — true of the raw corpus, and of `cog_explorer`'s conventions doc —
that rule does not apply to anything a `cog_*()` verb hands you. Applying it
twice overstates every figure by 1000x, and the result looks plausible rather
than obviously wrong.

## Configuration

- `USCOGDATA_URL` — corpus root URL (public Nextcloud share, trailing slash)
- `USCOGDATA_CACHE_DIR` — optional override for the manifest cache directory
- `USCOGDATA_MANIFEST_TTL_SECS` — optional manifest re-fetch TTL (default 3600)

## Primary vs Direct vs Total spending

`cog_spending(..., expenditure_concept = c("primary", "direct", "total"))`
controls whose spending a result counts. Concepts are defined as sets of the
crosswalk's `spend_subtype` values — never item-code first letters, which
cannot classify correctly (the letter `Y` alone spans revenue, expenditure,
and balance codes):

- `"primary"` (the default) is the government's own service provision:
  current operations, capital outlay, and assistance payments.
- `"direct"` is Census's published Direct Expenditure: `primary` plus
  interest on debt and insurance trust benefit payments (e.g. pensions).
- `"total"` additionally adds the intergovernmental leg — money handed to
  other governments to spend (`M`/`L` codes plus `Q11`/`Q12`/`Q18` state
  payments to school systems) — which is meaningful for describing one
  government's own budget over time, but double-counts when summed across
  governments (a state's payment to a county is the same dollar the county
  reports as its own direct spending).

**Rule of thumb: any figure that spans more than one government uses
`primary` or `direct`.** `cog_geographic_rollup()` and `cog_peer_compare()`
enforce this by refusing `expenditure_concept = "total"`. See
`vignette("total-spending", package = "uscogdata")` for the full
explanation with worked examples.

## Developer notes

### Testing

The package ships a bundled fixture corpus at `inst/extdata/fixture_corpus/` —
a 15 MB four-year slice (2011, 2012, 2019, 2020) of the full corpus covering
all 50 states. `tests/testthat/setup.R` automatically points `USCOGDATA_URL`
at this fixture, so the full test suite runs offline with no network
dependency:

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
