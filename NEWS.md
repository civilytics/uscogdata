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
