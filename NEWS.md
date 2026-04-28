# uscogdata 0.1.0 (development)

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
