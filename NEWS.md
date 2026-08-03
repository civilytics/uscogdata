# uscogdata 0.1.0 (development)

## New: `cog_balances()` for cash-and-security holdings

* New `cog_balances()` exposes the 14 cash-and-security holding codes
  (`category_type = "balance"`): fund balances, retirement system holdings and
  insurance trust balances (#25). Holdings are a stock, not a flow, so the verb
  has no `expenditure_concept` / `revenue_concept` / `complete` arguments, and
  no `subtype` argument either -- for holdings, `category` is a strict
  coarsening of `balance_subtype`, so `category = "Fund Balances"` is exactly
  the `general` family (`W01`/`W31`/`W61`).
* `cog_balances()` results carry `provenance$balance_caveats`, recording that
  Census holdings are gross rather than GAAP fund balance, and the measured
  coverage window of each subtype family.

## Multi-government aggregates now disclose their reporting coverage

* The Census of Governments is a **complete census only in years ending in 2
  and 7**; every other year is a sample, and the sample varies enormously. On
  the bundled fixture, Wisconsin's 608-city universe rolls up **597**
  governments in FY2012 and **112** in FY2019 — an 18%-to-98% swing the
  return value said nothing about, so a statewide total resting on a fifth of
  the universe looked exactly like one resting on all of it.
* `cog_geographic_rollup()`, `cog_peer_compare()` and `cog_find_peers()` gain
  `coverage`:

  | value | effect |
  |---|---|
  | `"all"` (default) | every unit that reported that year — unchanged behaviour |
  | `"census"` | census years only; aborts if the range holds none rather than returning nothing |
  | `"consistent"` | only units reporting in *every* requested year — a balanced panel |

* **Regardless of mode**, every result now carries `provenance$coverage` with
  per-year `n_units_reporting`, `n_units_expected` and `is_census_year`, plus
  `provenance$coverage_mode`. `cog_explain()` prints a "Reporting coverage"
  section. So the default mode can no longer mislead silently.
* `is_census_year` is a statement about the **survey calendar**, never a claim
  of completeness: FY1967 is a census year in which only 97 of Wisconsin's 608
  cities report. `n_units_reporting` is the number that tells the truth.
* On `cog_peer_compare()` the target is exempt from `"consistent"` balancing —
  it is the subject of the comparison, not a member of the cohort — and the
  `summary_*` quantiles are computed after the filter, so they describe the
  cohort actually returned. `n_units_reporting` counts peers only, against the
  cohort size.
* On `cog_find_peers()`, `coverage` governs the cohort **vintage** when `year`
  is `NULL`: `"census"` snaps to the most recent census year with an observed
  population, so a cohort is not built from a sample year in which most of the
  candidate universe is absent.

## `complete = TRUE`: absent cells, labelled with why they are absent

* `cog_spending()` and `cog_revenue()` gain `complete`, defaulting to `FALSE`
  (today's behaviour). With `complete = TRUE` the requested grid is filled
  from the corpus's `code_set` table and every row carries a new
  `value_source` column:

  | `value_source` | meaning | `amt_nominal` |
  |---|---|---|
  | `reported` | the corpus carries this cell | as published |
  | `census_zero` | dense-source year (≤ FY2011), cell absent — Census published `$0` | `0` |
  | `not_reported` | sparse-source year (≥ FY2012), cell absent — unknown | `NA` |

  The `NA` is deliberate and is the whole point: filling a modern absence
  with `0` would invent data, which is precisely the error the corpus's
  representation contract exists to prevent.
* This restores information the reader lost when the corpus was sparsified
  (`SB194`, cog_pipeline#64) — a wide-era query whose cells were all `$0`
  had begun returning nothing at all — and improves on what came before it,
  since the pre-sparsification corpus could not distinguish a published zero
  from an unreported cell either.
* The grid is scoped to each government's **own type**, so a county is never
  filled with cells only a state can report.
* Needs a corpus published from 2026-07-29 onward (when `representation` and
  `code_set` began shipping); aborts with class
  `uscogdata_representation_unavailable` otherwise. Gated on the manifest
  listing those tables rather than on `schema_version`, which was never
  bumped for the change. Not available with `recipe` or
  `expenditure_concept = "total"` — neither draws its cells from `code_set`.
* `provenance$completion` reports `applied`, `rows_filled`, and the per-year
  `absence_means` rule; `cog_explain()` prints a "Completion" section.

## Corpus-wide series breaks now reach users (`corpus_break_refs`)

* Four catalogued series breaks carry `fin_code = "ALL"` — caveats about the
  corpus as a whole rather than about one item code. `series_break_refs` is
  built by matching `fin_code` against the item codes in the result, and no
  row's `item_code` is ever the literal `"ALL"`, so **none of them could ever
  be surfaced**: `SB085` (dollar precision across the 1976/1977 boundary),
  `SB087` (imputation exclusion from FY2002), `SB194` (the dense → sparse
  representation change at FY2012) and `SB086` (the government id scheme
  change at FY2017).
* Provenance gains `corpus_break_refs`, selected on the break-year window
  alone and disjoint from `series_break_refs` by construction, so a consumer
  can tell a whole-result caveat from a break in one series. `cog_explain()`
  prints them under their own "Corpus-wide caveats" heading. cog-api passes
  provenance through verbatim, so the field appears there without an API
  change.
* `SB194` is the one that made this urgent: a query spanning FY2011 → FY2012
  crosses the boundary where an absent cell stops meaning "Census published
  `$0`" and starts meaning "not reported", and until now nothing said so.

## Bundled fixture regenerated against the sparsified corpus

* `inst/extdata/fixture_corpus/` now tracks the corpus published on
  2026-07-29 (`pipeline_commit 83f9715`, schema v6). The wide era no longer
  stores explicit zeros: FY2011 fell from 2,864,212 rows to 496,004, of
  which none are `$0`. **Absence now means two different things** — in a
  `dense_source` year (≤ FY2011) an absent cell means Census published `$0`;
  in a `sparse_source` year (≥ FY2012) it means not reported. The corpus
  carries that rule in two new tables the fixture now ships,
  `representation.parquet` and `code_set.parquet`, alongside
  `census_collection_coverage.parquet` and `lineage_events.parquet`
  (all ten publish-tree metadata tables, up from six). Catalogued upstream
  as series break `SB194`.
* `cog_categories()` gains an `assistance` spending subtype: the J-prefix
  aid/benefit codes (`J19`, `J67`, `J68`, `J85`) are categorised now that
  the upstream crosswalk covers every flow code carrying dollars.
* Two consequences worth knowing about, both visible in provenance rather
  than in returned dollars. The harmonization block's `na_rows_excluded`
  counts only rows that exist, so wide-era codes that were zero-padded no
  longer appear there. Coverage-gap `suggestions` are presence-based for the
  same reason, so a recipe whose component codes were all `$0` for a given
  government-year is no longer suggested for it.
* `tests/testthat/test-fixture-vintage.R` pins these structural facts, so a
  fixture left behind by a future publish fails loudly instead of letting the
  suite pass against a corpus that no longer exists.

## Breaking: corpus schema_version 4 (Phase P canonical ids)

* The package now requires corpus `schema_version = 4` (`MinCorpusSchema` /
  `MaxCorpusSchema` in `DESCRIPTION` are both `4`); older corpora built
  against schema 3 are rejected by `cog_open()` with a clear version-mismatch
  error. `canonical_govid` is now uniformly 12 characters across every
  vintage the corpus covers (previously a mix of 9-char legacy ids and
  12-char FIPS ids depending on source year) — **every hardcoded
  `canonical_govid` literal from a pre-Phase-P corpus is now invalid** and
  must be re-resolved via `cog_gov_search()` or the new `canonical_alias`
  lookup table. `canonical_fips_xwalk` gains four columns
  (`legacy_govs_id`, `census_geoid`, `id_source`; `confidence` is renamed to
  `pop_confidence`) and a companion `canonical_alias` table ships in the
  corpus for mapping legacy/alternate ids onto the current canonical
  namespace. The bundled fixture corpus (`inst/extdata/fixture_corpus/`) has
  been regenerated against the Phase P publish tree, now ships the full
  `canonical_fips_xwalk` and `canonical_alias` master tables alongside the
  2019-2020 long partitions, and is reproducible via
  `data-raw/regenerate_fixture_corpus.R`.

## Clearer errors when `USCOGDATA_URL` is unconfigured or returns non-JSON

* `cog_open()` now aborts with the `uscogdata_url_not_configured` error
  class when the resolved corpus URL still contains the placeholder
  `REPLACE_WITH_SHARE_TOKEN` sentinel (or is empty). The message lists both
  remediation paths (`Sys.setenv(USCOGDATA_URL = ...)` and
  `options(uscogdata.url = ...)`) and points at the bundled fixture for
  offline testing. Previously the package proceeded to fetch the placeholder
  URL, cached the resulting HTML welcome page, and failed downstream with a
  cryptic `jsonlite` lexical-error.
* `.fetch_or_cache_manifest()` now parses the HTTP response body before
  persisting it. Non-JSON responses (login pages, 404 HTML) raise
  `uscogdata_invalid_manifest` with the URL, Content-Type, and underlying
  parse error — and never write to the on-disk cache.
* Manifest cache writes are now atomic (write to `manifest.json.tmp.<pid>`
  in `cache_dir`, then `file.rename` over the target), so an interrupted
  fetch cannot replace a previously-good cache.
* Existing caches with non-JSON content (poisoned by the prior code path)
  are silently refetched instead of returning a parse error to the caller.
* Local `USCOGDATA_URL` paths whose `manifest.json` is not valid JSON now
  surface the same `uscogdata_invalid_manifest` class with file context.

## Per-capita denominators now use per-year Census F-33 population

* `cog_spending()` and `cog_revenue()` previously divided all years' amounts
  by a single ACS 2018-2022 estimate (`canonical_fips_xwalk.population_acs`),
  producing biased per-capita values for time-series analysis. They now
  divide by the F-33 `population` recorded on each gov-year via the new
  `gov_population_yearly` view. Result tibbles gain a `pop_source` column
  with values `"census_f33"` or `"unavailable"`. `notes` is updated to
  concatenate multiple notes with `"; "`.

## Peer cohorts can be set to a chosen year

* `cog_find_peers()` adds a `year` argument (default: most recent year for
  which the target has an observed population in `gov_population_yearly`).
  The returned column previously named `population_acs` is now `population`
  and reflects the cohort year's vintage. The cohort year is attached to the
  returned tibble as `attr(x, "cohort_year")`.
* `cog_peer_compare()` now stamps a `cohort_year` column on its result (read
  from the peers tibble's attribute) and records `cohort_year` plus
  `cohort_govids` in provenance. When the caller supplies a bare character
  vector instead of a `cog_find_peers()` result, `cohort_year` is `NA`.

## Rollups exclude govs missing population

* `cog_geographic_rollup(per_capita = TRUE)` drops rows whose government has
  `pop_source == "unavailable"` and records the dropped govids in
  `provenance$rollup$excluded_govids`. This excludes special districts
  (type 4) and school districts (type 5) from per-capita rollups by design.

## New: vignette and provenance metadata

* New vignette `population-denominators` covers the four population sources,
  the type-4/5 coverage gap, the popyear quirk, and how to build moving-window
  peer cohorts manually.
* Provenance gains `transformations$per_capita$popyear_range` and
  `pop_source_counts`. `cog_explain()` renders both.

## New features

* `cog_gov_search()` gains a **basket mode**: passing vector `name`
  / `state` / `type` arguments resolves multiple place names in one
  call and returns a tibble of canonical rows in input order, ready
  to pipe into `cog_spending()` / `cog_revenue()`. Per-row resolution
  follows an exact-then-substring matching algorithm with deterministic
  disambiguation; ambiguous and missing entries are surfaced via a
  sidecar audit tibble plus a single console summary message.
* New exports `cog_basket_resolution()` and `cog_basket_unresolved()`
  expose the basket sidecar for iterative query refinement.

## Breaking changes

* The first formal of `cog_gov_search()` was renamed from `pattern`
  to `name`. All existing call sites in `cog_explorer/` and the
  package itself use positional first-arg, so this rename is
  non-breaking in practice. Callers that pass `pattern = ...` by name
  must update to `name = ...`.
