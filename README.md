# uscogdata

<!-- badges: start -->
[![r-universe](https://civilytics.r-universe.dev/badges/uscogdata)](https://civilytics.r-universe.dev/uscogdata)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
<!-- badges: end -->

A curated R reader for the Civilytics US Census of Governments finance corpus —
every dollar that US state, county, municipal and township governments reported
raising and spending, from **FY1967 to FY2024**, in one queryable place.

The Census of Governments is the only nationwide source for local government
finance, and it is hard to use: item codes change meaning across vintages,
government identifiers were renumbered in 2017, and an absent value means
"published zero" in one era and "not reported" in the next. This package
handles each of those problems, and it tells you when it has — every result
carries provenance describing what was converted, what was aggregated, and
which known series breaks intersect your query.

**Scope:** government types 0–3 (state, county, municipality, township).
56 fiscal years, 46,148,034 rows, ~201 MB. There is no source data for FY1968
or FY1969. Special districts (type 4) and school districts (type 5) are
excluded pending validation.

## Where the data comes from

The corpus is published and documented at the **[US Census of Governments
Finance API](https://pages.civilytics.org/cog-api/)**. Start there for how the
data was built, how the identifier and item-code reconciliation works, and what
the corpus does and does not cover.

- **[API documentation and walkthroughs](https://pages.civilytics.org/cog-api/)**
  — reference, data dictionary, and worked examples such as the
  [Southern states guide](https://pages.civilytics.org/cog-api/cog-api-south-guide.html)
- **[Live API](https://cog-api.civilytics.org/api/v1/)** — the same corpus over
  HTTP, for Tableau, Python, or anything that isn't R
- **[Bulk corpus on Hugging Face](https://huggingface.co/datasets/civilytics/us-cog-finance)**
  — CC-BY-4.0; the same parquet files this package reads
- **[Census Bureau source data](https://www.census.gov/programs-surveys/gov-finances.html)**
  — the underlying public files

## Install

```r
install.packages("uscogdata",
  repos = c("https://civilytics.r-universe.dev",
            "https://cloud.r-project.org"))
```

Or from source:

```r
pak::pkg_install("git::https://gitea.civilytics.org/Civilytics/uscogdata.git")
```

## Quickstart

No configuration, no credentials, no download. The package reads the published
corpus over HTTPS by default.

```r
library(uscogdata)

# Resolve a place name to a canonical government id
madison <- cog_gov_search(name = "Madison", state = "WI", type = 2)
madison$canonical_govid
#> [1] "552025209777"

# Police spending, inflation-adjusted and per capita
spend <- cog_spending(
  madison$canonical_govid,
  years          = 2012:2022,
  category       = "Police",
  per_capita     = TRUE,
  adjust_to_year = 2023
)

# What did that result do to the numbers, and what should you know about them?
cog_explain(spend)
```

`years` is required — there is no implicit full-history default.

## Two ways to read the corpus

| | Remote (default) | Mirrored |
|---|---|---|
| Setup | none | `cog_mirror(dest)`, ~201 MB once |
| Disk used | **0 MB** — HTTP range requests only | ~201 MB |
| Opening a session | ~7.5 s | ~0.1 s |
| One government, one year | ~4 s | ~0.05 s |
| One government, full history | ~7 s | ~0.1 s |
| Later queries, same session | ~1.5 s | ~0.05 s |
| Good for | trying it out, teaching, one-off questions | repeated analysis, offline work, reproducibility |

**A local mirror is roughly 60–80x faster, and it is one function call.** That is
by far the largest difference any of these settings makes. If you are going to
ask more than a handful of questions, mirror first.

Measured 2026-08-10 on a 16-core Linux workstation against the published corpus
(schema v7, `pipeline_commit 3d28ddd`), fresh R session per arm. A one-off
question costs about **12 seconds end to end remotely and 0.15 seconds
mirrored**, session setup included.

Two things the per-query rows hide:

- **Opening the session is the single largest remote cost** — larger than any
  one query. It fetches the manifest and registers 23 SQL views over HTTPS, and
  it lands on your first query, not on `library(uscogdata)`.
- **The cost is network round-trips, not scanning.** A repeat query against
  partitions this session has already touched is ~1.5 s rather than ~4 s, and a
  full-history query costs ~7 s whether it runs first or last. What you are
  paying for is reaching each of the 56 yearly files over HTTPS the first time.

Nothing is written to disk in remote mode: DuckDB fetches the parquet footer,
works out which row groups it needs, and reads only those. Nothing is cached
between sessions either, so every query goes back to the network — and a session
that issues many remote queries in quick succession can be rate-limited by the
host (`HTTP Error: ... 429`). Both are further reasons to mirror for real work.

The default points at a public HuggingFace mirror of the corpus. If you would
rather not depend on a third party — for reproducibility, for an air-gapped
environment, or on principle — **the escape hatch is one function call**:

```r
cog_mirror("~/cog-corpus")
Sys.setenv(USCOGDATA_URL = "~/cog-corpus/")
```

After that, nothing in your analysis touches an external service.

### Configuration

- `USCOGDATA_URL` — corpus root: an HTTPS URL or a local path, **trailing slash required**
- `USCOGDATA_CACHE_DIR` — where the manifest is cached (default: user cache dir)
- `USCOGDATA_MANIFEST_TTL_SECS` — manifest re-fetch interval (default 3600)
- `USCOGDATA_DUCKDB_THREADS` — cap DuckDB's thread count (default: every visible core)
- `USCOGDATA_DUCKDB_MEMORY_LIMIT` — cap DuckDB's memory, e.g. `"4GB"` (default: DuckDB's own)

Each also has an `options()` spelling — `uscogdata.url`, `uscogdata.duckdb_threads`,
and so on — and the environment variable wins where both are set.

The two DuckDB caps exist for **servers**, not laptops. Unset, DuckDB claims every
core it can see, which is right for one interactive session on your own machine and
wrong when several readers share a box: each claims the whole machine and they fight.
Capping costs roughly 5% on a single query and is worth it anywhere the process is
sharing hardware.

## Amounts are in full US dollars

Every amount column this package returns — `amt_nominal`, `amt_real`,
`amt_per_capita_nominal`, `amt_per_capita_real` — is in **full US dollars**.

The raw Census source files report **thousands of dollars**, and the corpus's
own `amt` column preserves that. The verbs multiply by 1000 on the way out, so
you never have to. The conversion is recorded in every result:

```r
attr(spend, "provenance")$transformations$units_conversion
#> $applied     TRUE
#> $source_unit "$1,000s (raw Census)"
#> $target_unit "$USD"
#> $multiplier  1000
```

**Do not multiply again.** If you have read elsewhere that COG amounts are in
`$1,000s` — which is true of the raw Census files and of the corpus's own `amt`
column — that rule does not apply to anything a `cog_*()` verb hands you.
Applying it twice overstates every figure by 1000x, and the result looks
plausible rather than obviously wrong.

## Concepts worth understanding before you publish a number

### Primary vs Direct vs Total spending

`cog_spending(..., expenditure_concept = c("primary", "direct", "total"))`
controls *whose* spending a result counts. Concepts are defined as sets of the
crosswalk's `spend_subtype` values, never item-code first letters — the letter
`Y` alone spans revenue, expenditure and balance codes.

- **`"primary"`** (default) — the government's own service provision: current
  operations, capital outlay, assistance payments.
- **`"direct"`** — Census's published Direct Expenditure: `primary` plus
  interest on debt and insurance trust benefits (e.g. pensions).
- **`"total"`** — adds the intergovernmental leg, money handed to other
  governments to spend. Meaningful for one government's own budget over time,
  but it double-counts when summed across governments: a state's payment to a
  county is the same dollar the county reports as its own direct spending.

**Rule of thumb: any figure spanning more than one government uses `primary`
or `direct`.** `cog_geographic_rollup()` and `cog_peer_compare()` enforce that
by refusing `"total"` outright. Worked examples in
`vignette("total-spending", package = "uscogdata")`.

### General vs Total revenue

`cog_revenue(..., revenue_concept = c("general", "total"))`:

- **`"general"`** (default) — Census General Revenue: own-source taxes,
  charges and miscellaneous, plus federal, state and local aid.
- **`"total"`** — General plus utility revenue (`A91`–`A94`), liquor store
  revenue (`A90`), and insurance trust revenue.

Census defines these by its own identity:

```
Total Revenue = General + Utility + Liquor Store + Insurance Trust
```

Two things to know before switching to `"total"`. **Utility revenue is large
for cities** — measured on the bundled fixture, utility plus liquor store is
15.9% of city revenue, against 1.2% for states and 1.7% for counties. And the
**employee-retirement (`X`) codes stop at FY2016**, when those systems moved to
the separate Annual Survey of Public Pensions, so a `"total"` series steps down
at the FY2016/FY2017 boundary for reasons of collection scope, not revenue
(series breaks `SB197`–`SB209`).

### Reporting coverage: the Census is only sometimes a census

**The Census of Governments is a complete enumeration only in years ending in
2 and 7.** Every other year is a sample, and the sample varies enormously —
measured on the bundled fixture, Wisconsin's 608-city universe rolls up 597
governments in FY2012 and 112 in FY2019.

A statewide total resting on a fifth of the universe looks exactly like one
resting on all of it, so every multi-government result now says which it is:

```r
attr(rollup, "provenance")$coverage   # per-year n_units_reporting, is_census_year
```

`cog_geographic_rollup()`, `cog_peer_compare()` and `cog_find_peers()` take a
`coverage` argument — `"all"` (default), `"census"` (census years only), or
`"consistent"` (only units reporting in every requested year, a balanced
panel).

`n_units_reporting` is **category-conditional**, and it is not a response rate. A government that was surveyed and genuinely spends
nothing in the requested category is indistinguishable from one never surveyed.

### Absent cells mean two different things

Before FY2012, an absent cell means Census published `$0`. From FY2012 on, it
means not reported. `cog_spending(..., complete = TRUE)` fills the requested
grid and labels every row with which it is, via `value_source`:

| `value_source` | meaning | `amt_nominal` |
|---|---|---|
| `reported` | the corpus carries this cell | as published |
| `census_zero` | dense-source year (≤ FY2011), absent — Census published `$0` | `0` |
| `not_reported` | sparse-source year (≥ FY2012), absent — unknown | `NA` |

That `NA` is deliberate. Filling a modern absence with `0` would invent data.

### Series breaks surface on their own

Catalogued breaks that intersect your query appear in provenance whether or not
you went looking for them — `series_break_refs` for breaks in a specific item code, and
`corpus_break_refs` for caveats about the corpus as a whole (dollar precision
across the 1976/1977 boundary, the FY2017 identifier change, the FY2012
dense→sparse representation change). `cog_explain()` prints both.

## How to cite

```r
citation("uscogdata")
```

The corpus itself is published under CC-BY-4.0. Cite it as:

> Civilytics Consulting. US Census of Governments finance corpus.
> https://huggingface.co/datasets/civilytics/us-cog-finance

## Contributing

Development happens on [Gitea](https://gitea.civilytics.org/Civilytics/uscogdata);
[GitHub](https://github.com/civilytics/uscogdata) is a mirror that accepts
issues and pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md) for how a
patch gets from there to here.

## License

MIT © Civilytics Consulting LLC. See [LICENSE.md](LICENSE.md).
