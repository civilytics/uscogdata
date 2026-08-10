# uscogdata 0.4.0

## DuckDB's resource budget is configurable

`USCOGDATA_DUCKDB_THREADS` and `USCOGDATA_DUCKDB_MEMORY_LIMIT` (with matching
`options(uscogdata.duckdb_threads = )` / `options(uscogdata.duckdb_memory_limit = )`
spellings) cap the DuckDB connection the package opens. Both follow the same
env-var > option > default precedence as `USCOGDATA_URL`.

Unset, **no pragma is issued at all** and DuckDB's own defaults apply exactly as
before -- every visible core. That is right for one interactive session on a
dedicated machine and wrong for a server: where several readers share a host, each
otherwise claims the whole machine and they contend. Capping measured ~5% on a
single-government all-years query (502 ms at 2 threads vs 475 ms uncapped on 16
cores), which is cheap enough that a server should always cap.

This replaces a workaround in which a consumer reached into the package namespace
at boot -- `getFromNamespace(".ensure_session", "uscogdata")()` followed by a manual
`SET threads` -- depending both on a private name and on the session already being
open.

## `cog_gov_search()` and `cog_balances()` gain `limit`/`offset`

Pagination arrived on `cog_spending()`/`cog_revenue()` in 0.3.0; the other two
verbs were left materializing everything and slicing in R. Both now take
`limit`/`offset` with the same semantics: `NULL` default, the page applied in
SQL behind a deterministic `ORDER BY`, and the unpaginated count returned as a
`total_rows` attribute computed by `COUNT(*) OVER()` in the same scan rather
than a second query.

`cog_gov_search()` had no `LIMIT` at all, which made it the one verb that
returns the entire 40,336-row crosswalk when called with no filter.

Two refusals rather than silent surprises:

* `cog_balances(recipe = , limit = )` aborts with class
  `uscogdata_recipe_pagination_conflict` -- a recipe's result comes from a
  separate query that pagination is not wired into.
* `cog_gov_search()` in basket mode (`length(name) > 1`) aborts with class
  `uscogdata_basket_pagination_conflict`. Basket mode returns one resolved row
  per requested name with a sidecar covering all of them; a page of that is not
  a page of anything the caller asked for.

## Cohorts can be named by predicate, not just by id

`cog_spending()`, `cog_revenue()` and `cog_balances()` gain optional `state`
and `type` arguments. Both default to `NULL`, so every existing call behaves
exactly as before.

Passing them expresses the cohort as a subquery against `canonical_fips_xwalk`
inside each statement, instead of round-tripping the ids through R and
rendering them back into a literal `IN` list:

```r
# before: resolve 20,106 ids in R, then embed them in every statement
ids <- cog_gov_search(NULL, state = "CA", type = "city")$canonical_govid
cog_spending(ids, years = 2022)

# now: the cohort never leaves the database
cog_spending(years = 2022, state = "CA", type = "city")
```

Measured against the production corpus, same FY2022 aggregate over the
20,106-government `type = "city"` cohort:

| cohort expressed as | time |
|---|---:|
| `IN (20,106 literals)` | 449 ms |
| join against a temp cohort table | 99 ms |
| predicate on `canonical_fips_xwalk` | **94 ms** |
| no cohort filter at all (the floor) | 88 ms |

**4.8x, within 7% of the floor.** The rendered `IN` list was 301,591
characters and was re-parsed in 5-8 separate statements per call, so the cost
was paid repeatedly; the predicate's size is constant in the cohort.

`state` and `type` use the same vocabulary and the same internal coercion as
`cog_gov_search()` -- `state` is a postal abbreviation (`"WI"`) even though the
crosswalk column holds a FIPS code (`"55"`).

Supplying `govid` **and** `state`/`type` intersects them: the governments in
`govid` that also match the predicate. Naming no cohort at all now aborts with
class `uscogdata_no_cohort` rather than R's "argument is missing" error.

When the cohort is named by predicate there is no id list to report, so
`provenance$scope$govids_found`/`govids_missing` are empty and
`provenance$scope$cohort` carries `state`, `type` and `n_governments` instead.
A `govid`-named cohort's provenance is unchanged.

## Fixes

* `cog_gov_search()` now orders by `population_acs DESC NULLS LAST,
  canonical_govid`. **`population_acs` alone is not a total order** -- ties, and
  the entire `NULLS LAST` block, came back in whatever order the scan produced.
  That was invisible while every call returned the full result set, but it makes
  a paged sweep unsound: two requests can order tied rows differently, so a row
  is duplicated on one page and missing from the next. Unpaginated results are
  unchanged except for the relative order of rows that were already tied.

* An unknown `state` abbreviation now aborts with "Unknown state abbreviation"
  (class `uscogdata_unknown_state`) instead of base R's "subscript out of
  bounds". `.state_abbrev_to_fips` is a named character vector, so `[[` on an
  absent name threw before the curated message could be reached -- making that
  message unreachable dead code in every verb that takes a `state`.

# uscogdata 0.3.0

First public release.

`uscogdata` provides curated R verbs over the Civilytics US Census of
Governments finance corpus: unit-level financial profiles, geographic rollups
and peer comparisons, with auditable provenance on every result.

## What it covers

Government types 0-3 (state, county, municipality, township), FY1967-FY2024 --
56 fiscal years, 46,148,034 rows, 190.6 MB. There is no source data for FY1968
or FY1969. Special districts (type 4) and school districts (type 5) are out of
scope pending validation.

## The verbs

`cog_spending()`, `cog_revenue()` and `cog_balances()` for flows and holdings;
`cog_gov_search()` to resolve place names (including basket mode for many at
once); `cog_find_peers()` and `cog_peer_compare()` for cohorts;
`cog_geographic_rollup()` for aggregates; `cog_categories()`, `cog_recipes()`,
`cog_manifest()` and `cog_explain()` for metadata and provenance; and
`cog_mirror()` for a local copy of the corpus.

## Reading the corpus now works out of the box

* The package reads the published corpus over HTTPS **with no configuration**.
  Previously the default was a placeholder sentinel and no document in the
  package supplied a working URL, so a new user had no path to a session.
* Remote reads work at all. The partitioned view used a glob, and DuckDB
  cannot expand a glob over generic HTTP -- there is no directory listing to
  expand against. Partition paths are now enumerated from the corpus manifest,
  which is host-agnostic: an HTTPS mirror, a Nextcloud share and a local
  `cog_mirror()` copy all take the same path.
* Nothing is written to disk in remote mode; DuckDB fetches only the row
  groups a query needs.

## Four things to know before your first query

* **Amounts are in full US dollars.** The raw Census files report thousands;
  the verbs multiply by 1000 on the way out. Do not multiply again.
* **Multi-government aggregates disclose their coverage.** The Census is a
  complete enumeration only in years ending in 2 and 7; every other year is a
  sample. Every such result carries `provenance$coverage` with per-year
  `n_units_reporting`.
* **Absence means two different things.** Before FY2012 an absent cell means
  Census published $0; from FY2012 it means not reported. `complete = TRUE`
  labels which.
* **Series breaks reach you unasked.** Catalogued breaks intersecting your
  query appear in provenance and in `cog_explain()`.

## Known limits

* Special districts (type 4) and school districts (type 5) are out of scope.
* Per-capita rollups exclude governments with no F-33 population, which is by
  design but does silently narrow a rollup.
* `n_units_reporting` is category-conditional and is not a response rate.
* Employee-retirement (`X`) codes stop at FY2016, when those systems moved to
  the Annual Survey of Public Pensions.

# uscogdata 0.2.0

## New features

* `cog_spending()` and `cog_revenue()` accept the reserved category
  `"All Categories"`, returning one summed row per
  `(year, canonical_govid, subtype)` across every category inside the
  requested concept's subtype scope. Filtering the result to
  `spend_subtype == "operations"` gives an operating-expenditure total.
  `cog_geographic_rollup()` inherits it,
  which is the efficient way to build a geographic total — previously a
  caller had to issue one rollup per category and sum the results
  (cog-api#37).

  `"All Categories"` is not the same thing as `expenditure_concept = "total"`.
  The concept chooses which subtypes are in scope; `"All Categories"` chooses
  whether the rows inside that scope are broken out or summed.

* `cog_categories()` advertises `"All Categories"` for the expenditure and
  revenue vocabularies, so the reserved value is discoverable.

* Coverage signposting (see "Signposting now catches partially-suppressed
  categories" below) now also works in `category = "All Categories"` mode.
  The recipe-suggestion candidate query used to be scoped by `category`,
  which is never a match for the reserved `"All Categories"` value, so
  `provenance$suggestions` always came back empty there — the one mode whose
  whole point is "you cannot sum the wrong scope" was silently unable to
  signal a wrong scope. The candidate query is now scoped by the concept's
  subtype allowlist instead, symmetric with how `.build_verb_sql()` itself
  scopes the summed total: Los Angeles County FY2011, `category = "All
  Categories"` still excludes $271,589,000 of aggregate-published Public
  Welfare (`E68`), but now names `recipe = "welfare_cash_e68_wide"` to
  recover it instead of reporting zero suggestions.

## Documentation

* `cog_geographic_rollup()` and `cog_peer_compare()` now document that
  `provenance$coverage`'s `n_units_reporting` is **category-conditional** and
  is not a response rate: a government that was surveyed and genuinely spends
  nothing in the requested category is indistinguishable from one never
  surveyed (uscogdata#36).
