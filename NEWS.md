# uscogdata 0.1.0 (development)

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
