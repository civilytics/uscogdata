# Per-year population denominators in uscogdata

**Date:** 2026-04-29
**Status:** Design — pending implementation
**Scope:** uscogdata 0.1 (pre-release; no version bump)
**Related:** cog_pipeline (data dictionary updates)

## Problem

`uscogdata::cog_spending(per_capita = TRUE)` and `cog_revenue(per_capita = TRUE)`
currently divide every year's nominal amount by a single static population value
— `canonical_fips_xwalk.population_acs`, the ACS 2018-2022 5-year estimate.

For a 24-year corpus (2000–2023) this introduces a systematic bias proportional
to each government's population change over that span. Fast-growing places have
their early-year per-capita numbers understated; shrinking places have theirs
overstated. The bias commonly exceeds 20% and can exceed 50% for cities like
Detroit. Provenance currently advertises this denominator explicitly, so the
error is visible to careful users — but the default behavior produces wrong
numbers.

`cog_geographic_rollup()` has the same bug. `cog_find_peers()` /
`cog_peer_compare()` use the same static value to define peer cohorts, which
is defensible for matching but is no longer necessary now that per-year
population is available.

## Background — population sources

| Source | What it is | Where it lives |
|---|---|---|
| **Census F-33 `population`** | Population value Census uses on each COG row to compute its own per-capita tables. Almost always a Population Estimates Program (PEP) estimate; sometimes lagged a year for fiscal-year alignment, recorded in `popyear` | `long.population`, `long.popyear` (per row) |
| **PEP** (raw) | Census Bureau's official annual intercensal estimates. Distinct from F-33 because F-33 sometimes uses a lagged vintage | Not in corpus; available via tidycensus |
| **ACS 5-year** | American Community Survey 5-year rolling average. Different methodology, includes margin of error, only available 2005-2009 onward | `canonical_fips_xwalk.population_acs` (one fixed vintage) |
| **Decennial** | Actual count, every 10 years | Not in corpus |

F-33 `population` is the right default: it's what Census itself uses, so per-
capita results published by uscogdata reconcile with Census's own published
tables.

## Approach

Use the per-row `population` already present in `long`, joined on
`(canonical_govid, year)`. No new external data dependency. Coverage:

- **Types 0–3** (state, county, city, township): observed every year by design
- **Types 4–5** (special districts, schools): always NA — masked in
  `cog_pipeline/R/read_modern.R` because the F-33 schema does not carry a
  population value for these gov types

Type-4 and type-5 govs return `NA` per-capita with a `pop_source = "unavailable"`
flag and a note. No silent substitution.

The architecture leaves the door open for future denominators (PEP, ACS,
decennial) by surfacing `pop_source` as a first-class result column. Adding a
new source later is a join change, not an API change.

## Detailed design

### New view: `gov_population_yearly`

```sql
-- inst/sql/32-gov_population_yearly.sql
CREATE OR REPLACE VIEW gov_population_yearly AS
SELECT DISTINCT
  year,
  canonical_govid,
  population,
  popyear
FROM long
WHERE population IS NOT NULL;
```

`SELECT DISTINCT` collapses the metadata column duplicated across each gov-year's
item rows. A test asserts `(year, canonical_govid)` is unique to catch any
future source-data divergence.

### `cog_spending()` and `cog_revenue()`

`.attach_per_capita()` (in `R/spending.R`) is rewritten to:

1. Query `gov_population_yearly` for the requested govids and years.
2. `LEFT JOIN` on `(canonical_govid, year)` so missing rows produce NA.
3. Compute `amt_per_capita_nominal = amt_nominal / population`. NA when
   population is NA.
4. Drop `population` from the returned tibble (keep `pop_source` instead).

Result tibble gains one new column when `per_capita = TRUE`:

- `pop_source`: `"census_f33"` when a denominator was found, `"unavailable"`
  when NA.

`notes` is extended: when `pop_source == "unavailable"`, append
`"No population denominator available for this gov type"`. The `notes` column
is updated to concatenate multiple notes with `"; "` (it currently holds at
most one).

`amt_per_capita_real` is NA whenever `amt_per_capita_nominal` is NA.

### `cog_geographic_rollup()`

When rolling up spending or revenue with `per_capita = TRUE`:

1. Sum `amt_*` across contributing govs in the same year as today.
2. Sum `population` across contributing govs in the same year, **including only
   govs where both the funding variable and population are observed**.
3. Compute per-capita as `summed_amt / summed_population`.
4. When any contributing gov has missing population for a year, that gov is
   excluded from both the numerator and denominator for that year. The
   provenance records the excluded govids.

Documentation states explicitly: *Rollup totals include only governments
observed in both the finance and population panels for the given year. Special
districts and school districts (gov types 4 and 5) are therefore excluded from
per-capita rollups by design.*

Provenance gains:

- `rollup.included_govids` — those whose values were summed
- `rollup.excluded_govids` — those skipped due to missing pop
- `rollup.included_pop_total` — denominator used

### `cog_find_peers()`

Signature: `cog_find_peers(target_govid, year = NULL, pop_range = c(0.5, 2), ...)`

- `year` is a single integer. When `NULL`, defaults to the most recent year
  present in `gov_population_yearly` for the target.
- Looks up target's `population` at `year`. Errors if NA, with a message
  listing nearby years where target *is* observed.
- Filters candidates by `gov_population_yearly.population` at the same `year`,
  within `pop_range[1] * target_pop` and `pop_range[2] * target_pop`.
- Orders by `|log(pop_ratio)|` ascending.

Returned columns: `canonical_govid`, `gov_name`, `govs_type`, `fips_state`,
`population`, `pop_ratio`, `rank`. The column previously named `population_acs`
is renamed to `population`.

The cohort year is attached as a tibble attribute: `attr(x, "cohort_year")`.

### `cog_peer_compare()`

Signature: `cog_peer_compare(target_govid, years, ..., cohort_year = NULL)`

- `cohort_year` is a single integer; defaults to the most recent year in the
  corpus for the target.
- Builds a fixed cohort via one call to `cog_find_peers(target_govid,
  year = cohort_year, ...)`.
- Calls `cog_spending(c(target, peers), years, ...)` for the user's full
  `years` range against that fixed cohort.
- Result tibble includes a constant `cohort_year` column for visibility.

Users who want time-varying cohorts can loop over years themselves and stitch
results — documented in the vignette with a worked example.

### Provenance updates

`provenance$transformations$per_capita` becomes:

```r
list(
  applied = TRUE,
  denominator_source = "Census F-33 population (per-year, from long.population)",
  popyear_range = c(<min>, <max>),
  pop_source_counts = list(census_f33 = N1, unavailable = N2)
)
```

For peer compare results, additional provenance:

```r
list(
  cohort_year = <int>,
  cohort_govids = <character>,
  pop_range = c(<lo>, <hi>)
)
```

For rollup results, additional provenance:

```r
list(
  rollup = list(
    included_govids = <character>,
    excluded_govids = <character>,
    included_pop_total = <int>
  )
)
```

`R/explain.R` is updated to render the new fields.

### Documentation

**New vignette** `vignettes/population-denominators.Rmd`:

1. The four population sources explained
2. Why F-33 is the default — and how it reconciles with Census's own per-capita
   tables
3. The `popyear` quirk: Census sometimes uses a lagged estimate for fiscal-year
   alignment. Recorded in provenance, not in the result.
4. Worked example showing the bias from the old static-ACS approach versus
   per-year F-33 (e.g., Detroit 2003 vs. 2023)
5. Worked example of a rolling-cohort peer comparison built by looping
   `cog_peer_compare()` per year
6. Future direction: `pop_source` is structured so PEP, ACS time-series, or
   decennial denominators can be added later without API changes

**`cog_pipeline/docs/data_dictionary.md`** entry for `long.population` and
`long.popyear`: definition, source (F-33 fixed-width files, byte ranges),
type-4/5 masking rule, relationship to PEP.

### Tests

- `gov_population_yearly` returns one row per `(year, canonical_govid)` (uniqueness)
- `cog_spending(per_capita = TRUE)` returns different denominators for
  different years for a known gov in the fixture (use any gov whose population
  changes between 2019 and 2020)
- Type-4 and type-5 govids in the fixture return `pop_source = "unavailable"`
  and `NA` per-capita with the expected note
- `cog_geographic_rollup(per_capita = TRUE)` excludes missing-pop govs and
  records them in provenance
- `cog_find_peers()` defaults `year` to the most recent year for a target
  with known population history
- `cog_find_peers()` errors with a helpful message when target has no observed
  population in the requested year
- `cog_peer_compare()` defaults `cohort_year` and produces a result with a
  constant `cohort_year` column
- Provenance carries `denominator_source`, `popyear_range`, and
  `pop_source_counts`
- Regression test against a fixed govid+year showing the new per-capita value
  differs from the old (static-ACS) by exactly the ratio of `population_acs`
  to `long.population` for that gov-year

### Migration

Pre-release; no version bump. `NEWS.md` Unreleased entry:

> **Per-capita denominators now use per-year Census F-33 population.**
> Previously, `cog_spending()` and `cog_revenue()` divided all years' amounts
> by a single ACS 2018-2022 population, producing biased per-capita values
> for time-series. They now divide by the F-33 `population` recorded for each
> gov-year. Type-4 (special districts) and type-5 (school districts) govs
> return `NA` per-capita with `pop_source = "unavailable"`.
>
> **Peer matching now uses per-year population.** `cog_find_peers()` gains a
> `year` argument (defaults to most recent observed year). `cog_peer_compare()`
> gains `cohort_year`. Cohorts are still fixed for a single peer-compare call;
> users wanting moving cohorts loop themselves.
>
> **Rollups exclude govs with missing population.** `cog_geographic_rollup()`
> per-capita totals include only govs where both the finance variable and
> population are observed in that year; excluded govids are recorded in
> provenance.
>
> Returned column `population_acs` from `cog_find_peers()` is renamed to
> `population` and reflects the cohort-year vintage.

### File impact

| File | Change |
|---|---|
| `inst/sql/32-gov_population_yearly.sql` | New |
| `R/spending.R` (`.attach_per_capita`, `.notes_column`) | Per-year join, `pop_source`, multi-note concat |
| `R/peers.R` (`cog_find_peers`, `cog_peer_compare`) | `year` / `cohort_year` args, query new view, column rename |
| `R/rollup.R` | Skip-with-record for missing-pop govs |
| `R/provenance.R` | New denominator/cohort/rollup fields |
| `R/explain.R` | Render new fields |
| `vignettes/population-denominators.Rmd` | New |
| `tests/testthat/` | Per-year denominator, type-4/5, rollup exclusion, peer cohort, provenance |
| `cog_pipeline/docs/data_dictionary.md` | Document `long.population`, `long.popyear`, masking |
| `NEWS.md` | Unreleased entry |

## Out of scope

- PEP/ACS/decennial denominators — architected for, not implemented
- `per_pupil` denominator using `long.enrollment` for type-5 — deferred
- Covering-county fallback for type-4 — deliberately not done
- Backfilling population for type-4/5 from any external source
- Changes to `cog_explorer` callers — separate follow-up, after this lands
