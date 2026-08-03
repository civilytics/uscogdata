# `cog_balances()` — a reader surface for cash and security holdings

**Issue:** `uscogdata#25` requirement 2 · **Downstream:** `cog-api#26`
**Date:** 2026-08-03 · **Status:** design, awaiting approval

Requirement 1 of `uscogdata#25` (no `balance` row may reach a money verb) shipped
with `#11`/`#12` and is asserted at both view and verb level. This spec covers
requirement 2 only: a way to query holdings.

## Decision: a verb, not an argument

`cog_balances()`, parallel to `cog_spending()` / `cog_revenue()`.

Holdings are a **stock** — a balance at a point in time — while the money verbs
return **flows** over a fiscal year. The flow verbs' whole argument vocabulary
is meaningless for a stock: `expenditure_concept` / `revenue_concept` describe
which flows Census aggregates into a published total, and `complete=` fills a
grid of fiscal-year cells. Overloading a money verb would put a stock behind
arguments that all assume a flow.

## The 14 codes

Measured against the published corpus 2026-08-03, not transcribed from the
issue. `year_min`/`year_max` are observed row extents.

| `balance_subtype` | `category` | codes | observed years |
|---|---|---|---|
| `general` | Fund Balances | `W01`, `W31`, `W61` | 2012–2021 |
| `employee_retirement` | Retirement System Holdings | `X21`, `X42`, `X44` | 1967–2016 |
| | | `X47` | 1988–2016 |
| | | `X30`, `Z77`, `Z78` | 2012–2016 |
| `unemployment_trust` | Insurance Trust Balances | `Y07`, `Y08` | 1967–2023 |
| `workers_comp_trust` | Insurance Trust Balances | `Y21` | 2012–2023 |
| `other_insurance_trust` | Insurance Trust Balances | `Y61` | 2012–2023 |

## Architecture

### Two new views

Mirroring the `revenue_long` / `revenue_annotated` pair exactly:

- `inst/sql/26-balance_long.sql` — `category_type = 'balance' AND NOT is_aggregate`
- `inst/sql/46-balance_annotated.sql` — joins `canonical_fips_xwalk` and
  `summary_categories`, exposing `category`, `category_type`, `balance_subtype`

`.register_views()` globs `inst/sql/*.sql` in sorted order, so both register
with no new registration code.

### A third gate list in `R/views.R`

`CREATE VIEW` resolves its source schema eagerly, so a missing **column** fails
at registration time, not at query time. `46-balance_annotated.sql` selects
`c.balance_subtype`, which exists only on corpora built after pipeline `#76`/`#77`.
That arrived without a `schema_version` bump, so neither existing gate applies:
`.harmonization_view_files` keys on `schema_version`, `.representation_view_files`
on the presence of a *file*. The discriminator here is a **column on an existing
table**.

```r
.balance_view_files <- c("26-balance_long.sql", "46-balance_annotated.sql")
```

gated by probing `summary_categories` for `balance_subtype`, with
`cog_balances()` erroring cleanly via `.require_balance_support()` on an older
corpus — mirroring how `.require_schema_v5()` gates the harmonized views.

### `R/balances.R` — a dedicated path, not `.verb_spendrev()`

`.verb_spendrev()` is 825 lines whose concept scoping, intergovernmental leg and
`complete=` grid are all flow-specific, and four verbs depend on it. Threading a
third mode through it adds branching to shared code for no reuse benefit.

Reused unchanged: `.build_provenance()`, `.build_series_break_refs()`,
`.build_corpus_break_refs()`, the population join, `.inflate()`, and
`.coerce_govid_input()`.

Following the package's real two-layer convention: **view definitions** live in
`inst/sql/`; **query construction** is inline `sprintf()` in R, as in
`.verb_spendrev()`. (`CLAUDE.md` currently states "never inline SQL strings in R
files", which the verb layer has never obeyed. Corrected in a separate commit —
see Out of scope.)

## Signature

```r
cog_balances(govid, years,
             category       = NULL,   # Fund Balances | Insurance Trust Balances |
                                      # Retirement System Holdings
             per_capita     = FALSE,
             adjust_to_year = NULL,
             basis          = c("harmonized", "raw"))
```

Returns a `tbl_df` with a `provenance` attribute, like every other verb.

**Absent by design:** `expenditure_concept`, `revenue_concept`, `complete`,
and `subtype` — see below.

**`per_capita` is offered.** Holdings per resident is a real measure (pension
assets per capita, fund balance per resident). The roxygen `@param` states
plainly that this is a *stock per resident* and is **not** comparable to
`cog_spending()`'s per-capita figures.

**`basis` is currently a no-op** — `harmonization_map` has zero balance-code
rows, so harmonized and raw are identical for holdings. Kept for uniformity
with the money verbs (the API would otherwise special-case), and
`provenance$basis_note` says so outright rather than letting it look meaningful.

**`recipe` is deliberately omitted from v1.** See below.

### No `subtype` argument: `category` is a strict coarsening

`balance` is the only `category_type` in which `category` and the subtype column
are **not** orthogonal. Measured against the published crosswalk:

| `category_type` | subtypes spanning more than one category |
|---|---|
| expenditure | 5 of 6 (`operations`, `capital`, `interest`, `assistance`, `intergovernmental`) |
| revenue | 1 of 7 (`own_source`) |
| **balance** | **0 of 5** |

For expenditure the two axes are a genuine cross-tab — *function* (Police, Fire)
× *economic character* (operations, capital) — so both earn their place. For
balance the relation is a strict tree:

```
Fund Balances              = {general}                                W01 W31 W61
Retirement System Holdings = {employee_retirement}                    X21 X30 X42 X44 X47 Z77 Z78
Insurance Trust Balances   = {unemployment_trust,
                              workers_comp_trust,
                              other_insurance_trust}                  Y07 Y08 Y21 Y61
```

Exposing both would therefore admit no useful combination. Of the 15 possible
pairs, 3 are redundant (the subtype already implies its category) and **12 are
guaranteed empty for every government in every year** — and an impossible query
would fail by returning an empty tibble, which reads as "this government holds
none" rather than "you asked a contradiction."

Dropping `subtype` also keeps the verb aligned with the rest of the package: no
uscogdata verb exposes a subtype argument. `subtype_col` is internal plumbing in
`.verb_spendrev()`, and the API layers its own `subtype` row filter on top
(`api/R/handlers_governments.R`). `cog-api#26` can do exactly that for
`/balances`.

`#25`'s hard requirement is still met — `category = "Fund Balances"` *is* the
`general` family, precisely `W01`/`W31`/`W61`, in one filter. The only loss is
isolating one of the three insurance funds in a single argument;
`balance_subtype` remains a returned column, so that is one `dplyr::filter()`
away.

## Decision point: `recipe=` deferred to v2

The two holdings recipes are unusable from this verb today, and shipping the
argument anyway would produce a silently truncated series.

`cash_securities_z77_wide` = `X40` (1967–2011) + `Z77` (2012–2023);
`cash_securities_z78_wide` = `X41` (1967–2011) + `Z78` (2012–2023).

**`X40` and `X41` have zero rows in `summary_categories`.** They carry ~42,700
rows in the corpus across 1967–2011, but with no `category_type` they cannot
appear in a `category_type = 'balance'` view. Applying either recipe would
return only the modern leg — 2012–2016 — dropping 45 years while looking like a
valid continuous series. That is precisely the "plausible rather than obviously
wrong" failure mode `#25` exists to prevent.

The fix is upstream, in the pipeline crosswalk. Until it lands, `cog_balances()`
does not accept `recipe`, and an attempt to pass one is an error naming the
blocking issue rather than a silent partial result.

## Caveat surfacing

`provenance$balance_caveats`, always present, plus one `cli_inform()` per
session per caveat class when a query actually touches an affected family or
year. Structured so `cog-api#26` can forward the fields verbatim.

Three of the four caveats need reader-side work. **My earlier assumption that the
catalogued series breaks would cover them is wrong**, verified against
`series_breaks.parquet`:

| # | Caveat | Covered by existing machinery? |
|---|---|---|
| 1 | Gross holdings, **not GAAP fund balance**; no liabilities netted | No — constant, new field `not_gaap = TRUE` |
| 2 | `W` is FY2012–2021 only | No — new `coverage_window`, **computed** from the corpus |
| 3 | `X`/`Z` family ends FY2016 | **No.** SB197–SB202 attach to `X02`/`X05`/`X08`/`X11`/`X12`, which are *flow* codes. The holdings codes have no catalogued break for their FY2016 termination. Surfaced via `coverage_window` |
| 4 | `X40`/`X41` book → market at FY2002 | **No.** SB195/SB196 attach to `fin_code` `X40`/`X41`, which are outside the balance view (see above). Surfaced as an explicit caveat when the year range crosses 2002 and touches `employee_retirement` |

`coverage_window` is derived per observed subtype family from the corpus, never
hardcoded, so it stays correct as the corpus grows.

`series_break_refs` and `corpus_break_refs` are still populated by the existing
code-driven builders — they simply contribute nothing for the four caveats
above, and will start contributing once the upstream gaps close.

## Testing

New `tests/testthat/test-balances.R`. The bundled fixture covers all four
fixture years — `W` in 2012/2019/2020, the `X`/`Z` family in 2011/2012, `Y`
throughout — so every test below runs offline.

- **Inverse guard.** No flow code ever appears in `cog_balances()`, complementing
  the already-asserted forward guard. Absence is verified against the raw corpus
  via `read_parquet` on `data/long`, never through the verb that creates it.
- **FY2016 seam.** The `X`/`Z` family is present in 2012 and absent in 2019;
  `coverage_window` reports the termination and the console message fires once.
- **Caveats.** `not_gaap` is always `TRUE`; `coverage_window` matches the
  measured table above; the FY2002 valuation caveat fires only when the year
  range crosses 2002 *and* touches `employee_retirement`.
- **`per_capita`.** `amt_per_capita_nominal == amt_nominal / population`.
- **`category = "Fund Balances"` is the `general` family.** Returns exactly
  `W01`/`W31`/`W61` and nothing else — `#25`'s one-filter requirement, asserted
  rather than assumed.
- **The hierarchy holds.** Every `balance_subtype` in the crosswalk maps to
  exactly one `category`. Asserted against the crosswalk so that an upstream
  change breaking the tree — which would silently make `category` lossy —
  fails here rather than in a user's analysis.
- **`recipe` rejection.** Passing `recipe` errors with a message naming the
  blocking issue.
- **Gating.** `.require_balance_support()` errors cleanly on a corpus whose
  `summary_categories` lacks `balance_subtype`.

## Out of scope, tracked separately

1. **Pipeline issue (new).** Add `summary_categories` rows for `X40`/`X41`
   (`category_type = 'balance'`, `balance_subtype = 'employee_retirement'`), and
   catalogue a series break for the FY2016 termination of the holdings codes.
   Unblocks `recipe=` and lets caveats 3 and 4 flow through the existing
   builders. Requires a corpus rebuild + republish, which is a separate,
   human-approved operation.
2. **`cog-api#26`.** Adds `/balances` in all three required places — handler,
   `param_contract`, and the `plumber.R` route signature. Lands after this.
3. **`uscogdata/CLAUDE.md` refresh.** Separate commit. It is stale: it claims 7
   SQL views (there are 21), 181 tests (716), a two-year fixture (four years),
   and a "never inline SQL" rule the verb layer does not follow.
