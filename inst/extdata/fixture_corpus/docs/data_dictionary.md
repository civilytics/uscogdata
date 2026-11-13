# Data dictionary

> **Goal:** A continuous 1967–present time series of U.S. Census of Governments
> finance data, with every variable that can be aligned across the entire
> period aligned, and every variable that cannot be aligned explicitly
> documented.

## "Total spending": Direct, Total, and the M-code

"What was total spending?" is a first-class question with two legitimate answers,
and which one is correct depends on the shape of the question. This section is the
authoritative definition; every user-facing surface (the API, `uscogdata`) should
resolve "total spending" to the concept described here.

**The two concepts.** For every spending function (corrections, police, health, …):

- **Direct** — a government's *own* spending on the function: the sum of its
  current-operations, construction, and other-capital outlays (the `E`/`F`/`G`
  leaf codes, e.g. `E05`/`F05`/`G05` for corrections). The **legacy era**
  (≤ FY2011) also carries this pre-summed as the function's **family aggregate**
  `-NN` (e.g. `-05`); the **modern era** (FY2012+) is leaf-only, so Direct there
  is the `E`/`F`/`G` sum.
- **Total** — Direct **plus** the function's **intergovernmental payments** to
  *other* governments: the **`M`-code** (payments to **local** governments,
  e.g. `M05`) plus the **`L`-code** (payments to **state** governments, e.g.
  `L05`). This is Census's "Total".
- The identity **`Total = Direct + M + L`** holds arithmetically, and both IG
  families are published in **both** eras — but that does not mean Total is
  always "one line of arithmetic" away from a leaf-row query. In the
  **legacy era (≤ FY2011)** several IG code families — `M05`, `M12`, `M47`,
  `M89`, `L47`, `L89` — are published **only** as `is_aggregate = TRUE` rows,
  because the wide source files expose those families only as aggregates
  (their leaves first appear in the modern era). Measured on the published
  corpus: in FY2007 only **26.3%** of intergovernmental dollars sit on
  non-aggregate rows (129,835,142 of 493,510,366). `M12` alone is
  291,293,845 that year — 59% of the year's IG total — and is
  `is_aggregate = TRUE`, as are `M89`, `M47`, and `L--`. A reader that filters
  `!is_aggregate` and then sums M/L leaves therefore sees only a minority of
  legacy IG dollars and silently reconstructs a "Total" that is ≈ Direct.
  Total must instead be assembled **year-scoped**, the way
  `ige_local_m47_wide`, `ige_local_m89_wide`, `ige_state_l47_wide`,
  `ige_state_l89_wide`, and `corrections_ig_local_combined` already do.
- `L ≡ 0` for state governments, so for a state `Total = Direct + M`. For
  **local** governments `L` is material and must not be dropped: measured over
  the corpus, `L` is **91.6%** of `M` for counties and **188.3%** for cities.

**What the corpus publishes.** For each legacy family aggregate, exactly **one
flavor — Direct** (and the H2-designated column for the corpus-wide
`E--`/`F--`/`G--` totals). The M- and L-codes ship alongside in both eras, so a
consumer who wants Census Total adds the matching M- and L-codes. This
one-flavor rule is the #28 "Option B" ruling, applied in the v6 rebuild of
2026-07-23; before it, a family's Direct and Total flavors shared a single
`item_code` (a silent double-count hazard) — see
[`series_breaks.md`](series_breaks.md#direct-vs-total).

**Which concept for which question.** The dividing line is whether the query sums
across *governments*:

| Question shape | Concept to use | Why |
|---|---|---|
| One government over time (*"my county's corrections spending, 2017 vs today"*) | Either — Direct or Total, applied **consistently** | no cross-government summing, so either is internally valid; just don't switch concepts between years |
| Roll up many governments (*"all the counties in my state"*) | **Direct only** | summing Total double-counts intergovernmental flows: a state grant is in the state's Total **and** is spent again as the recipient's Direct |
| Compare aggregates across states (*"my state vs the one next door"*) | **Direct only** | same reason — every cross-government sum must be Direct |

Rule of thumb: **any sum that spans more than one government uses Direct.** Total
is safe only for a single government (or that government's own trend).

**Worked example — Alabama state government, corrections, FY2007** (legacy era;
amounts in $1,000s, from the published corpus):

| Item | Value | Meaning |
|---|---:|---|
| `E05` + `F05` + `G05` | 479,452 + 2,049 + 5,674 = **487,175** | the leaf triple |
| `-05` | **487,175** | **Direct** — the published legacy family aggregate (= the leaf triple) |
| `M05` | **27,210** | intergovernmental payments to other **local** governments |
| `L05` | **0** | intergovernmental payments to **state** governments (always 0 for a state government) |
| Direct + `M05` + `L05` | **514,385** | **Total** (Census's concept) |

"Alabama's total corrections spending in FY2007" is **487,175** (Direct) or
**514,385** (Total) — both valid for Alabama alone. But "corrections spending by
Alabama *and its counties*" must sum each government's **Direct**, or the $27,210
the state paid its localities is counted twice. In modern years (FY2012+), which
carry no `-NN` aggregate, take Direct as the `E`/`F`/`G` leaf sum for the
function.

Alabama is a *state* government, so its `L05` is 0 and Total reduces to
Direct + `M05`. For a **city or county**, the `L` term is material — omitting
it understates Total.

## Source data files

| Source | Years | Format | Loaded by |
|--------|-------|--------|-----------|
| `IndFin{yy}{a,b,c}.Txt` (historical IndFin) | 1967, 1970–2012 | Wide ASCII CSV, three files per year | This pipeline (Phases B–E) |
| Individual unit files | 2012–present | Long format with `item_code` + `amt` | `cog_explorer/R/01_data.R` |

The two source families overlap at 2012, so we have one year of validation
where both pipelines should produce equivalent values. Historical files use
abbreviated **display-name** column headers (e.g. `"Total Rev-Own Sources"`)
that must be reconciled to **`sas_dbf`** labels (e.g. `TotRev_Own`) to match
the modern long-format pivot. The reconciliation procedure is documented in
[archive/reconciliation_task.md](archive/reconciliation_task.md).

## Crosswalks

| File | Purpose |
|------|---------|
| [`data/wide_to_long_xwalk.csv`](../data/wide_to_long_xwalk.csv) | Master 681-row crosswalk: `sas_dbf, sas_var, fin_code, full_desc, sas_type, is_derived, is_aggregate, s2k_comp` |
| [`data/wide_derived_formulas.csv`](../data/wide_derived_formulas.csv) | 135 SAS-style derivation formulas for calculable (computed) variables |
| [`data/display_to_sas_dbf.csv`](../data/display_to_sas_dbf.csv) | 553-row mapping from IndFin .Txt display-name headers → `sas_dbf` (built positionally from UserGuide; see [archive/reconciliation_task.md](archive/reconciliation_task.md)) |
| [`data/series_breaks.csv`](../data/series_breaks.csv) | **196-row catalog of every known boundary where Census changed series definitions, with explicit join verdicts.** See [series_breaks.md](series_breaks.md). |
| [`data/id_crosswalk.csv`](../data/id_crosswalk.csv) | Maps pre-2017 9-char GOVS IDs ↔ post-2017 12-char Census IDs. Built from `IDxWalk.Txt` + `ALLids.csv` + LILP crosswalk. |

## Variable categories

- **Reference variables** — `SurveyYear`, `Year4`, `ID`, `StateCode`, `TypeCode`, `County`, `Name`, `CensusReg`, `FIPS_State`, `Weight`, `FYEndDate`, `YearData`, `YearPop`, `YearDepSch`, `YearRetire`, `SchLevCode`, `Version`, `ReviseDate`, `Data_Flag`, `JacketUnit`, `ZeroData`, `Imputed`, `Population`. Stable across all years.
- **Stored finance variables** — 553 in legacy IndFin (per [`docs/userguide/02_variables.md`](userguide/02_variables.md)). Some have series breaks at FY2005 (see below).
- **Derived (calculable) variables** — 135 formulas in `wide_derived_formulas.csv`. Computed from stored variables. Subject to ±1 rounding for FY1967–1976 data (see series_breaks SB085).

## Expenditure and revenue subtypes: the `I`, `Q` and `Y` flow codes

Added 2026-07-30 as the crosswalk prerequisite for `uscogdata#11`'s
three-concept expenditure model:

```
total   = primary + interest + intergovernmental transfers
direct  = primary + interest                 (Census's published Direct Expenditure)
primary = direct minus debt service          (the reader's new default)
```

`primary` is computable only because `interest` is a distinct subtype — it is
the marker separating debt service from the rest of direct expenditure, exactly
as `intergovernmental` separates direct from total.

### The full subtype vocabulary

| `spend_subtype` | codes | note |
|---|---|---|
| `operations` | `E*` | |
| `capital` | `F*`, `G*` | |
| `assistance` | `J*` | cash paid to individuals (#58/#60) |
| `intergovernmental` | `M*`, `L*`, `Q*` | money handed to another government |
| `interest` | `I89`, `I91`–`I94` | debt service; what `primary` excludes |
| `insurance_benefits` | `Y05`, `Y06`, `Y14`, `Y53`, `X11`, `X12` | social insurance trust payouts; `X*` **new** (#12) |

| `revenue_subtype` | codes | note |
|---|---|---|
| `own_source` | `T*`, `A*` (except `A90`–`A94`), `U*` | |
| `federal` / `state` / `local_aid` | `B*` / `C*` / `D*` | |
| `utility` | `A91`–`A94` | **new** (#12) — water, electric, gas, transit |
| `liquor_store` | `A90` | **new** (#12) |
| `insurance_trust` | `Y01`, `Y02`, `Y04`, `Y11`, `Y12`, `Y51`, `Y52`, `X01`, `X02`, `X05`, `X08` | `X*` **new** (#12) — see below |

**The four non-general revenue subtypes exist so both published Census concepts
are computable.** Census defines one by subtracting from the other (manual
§4.3: *"General revenue comprises all revenue except that classified as liquor
store, utility, or insurance trust revenue"*), giving the identity

```
Total Revenue = General + Utility + Liquor Store + Insurance Trust
```

Verified against Census's own computed concept fields (IndFin FY2012, Wisconsin
state): `31,410,686 + 0 + 0 + 4,469,906 = 35,880,592`, exact. Before
uscogdata#12, utility and liquor store revenue sat in `own_source`, so summing
the "general" subtypes actually produced *General + Utility + Liquor* — a
concept Census does not publish. Bucketing `Y01`/`X01` as own-source would
likewise fold trust contributions into general-revenue totals under a name
saying they are the government's own money.

**Employee retirement (`X*`) is the same concept as `Y*`, split only by which
trust system pays.** `X01`/`X02` (employee contributions), `X05` (contributions
from other governments) and `X08` (earnings on investments) are insurance trust
*revenue*; `X11` (benefit payments) and `X12` (withdrawals) are insurance trust
*expenditure*, and they sit **inside Census's Direct Expenditure** — the
manual's X11/X12 function page lists its coding options verbatim as *"Direct
Expenditure: X11 Benefit Payments, X12 Withdrawals / Intergovernmental
Expenditure: None"*, and §5.2.2.1 defines Direct as *"all final expenditures
paid to current employees, former employees (retirees) … all expenditure other
than intergovernmental"*. Verified: Census's "Total Insur Trust Ben" for
Wisconsin FY2012 ($5,946,605K) equals `X11 + X12 + Y05 + Y06 + Y14` to the
dollar, and Census's "Total Emp Ret Rev" ($2,283,883K) equals
`X01 + X02 + X05 + X08` to the dollar.

**Five `X` codes are deliberately unmapped.** `X04` and `X06` are exhibit codes
for *intragovernmental* transfers (the administering government paying its own
fund) — `X05`'s own definition excludes them by name, and Census's Total Emp Ret
Rev omits them, which is why the identity above closes without them. `X09`
merged into `X08` at FY1990 ($12K total). `X14` is an exhibit code explicitly
*"not included in C995"*. `X35` is a disjoint sibling of `X44`, not its child
(SB181). Locked by a test rather than left implicit.

**The `X` family stops at FY2016** (SB197–SB202): employee retirement systems
moved out of the annual finance file into the separate Annual Survey of Public
Pensions. Any `direct`/`total` expenditure or `total` revenue series steps at
the FY2016/FY2017 seam — a collection-scope change, not a real one. Catalogued
as `coverage_restricted`, not `discontinued`: the codes' identity never changes,
so there is no successor to bridge and they stay identity-harmonized across
their whole life.

**Utility/liquor revenue keeps `category = "Current Charges"`.** Only the
subtype moved. H6 (`summarize_spike_state()`) groups by `category` *without*
`category_type`, so re-filing `A91` under the functional category its `E/F/G/I`
siblings use ("Water Utilities") would sum utility revenue into the same
publish-gate cell as utility expenditure. Re-categorising is a separate change
that must move that gate deliberately.

### Prefixes `Y` and `X` each span all three `category_type`s

This is finding F-018, and it is why classification is per-code rather than by
first letter. Two letters, three flows each:

| codes | `category_type` |
|---|---|
| `Y01`, `Y02`, `Y04`, `Y11`, `Y12`, `Y51`, `Y52` | `revenue` |
| `Y05`, `Y06`, `Y14`, `Y53` | `expenditure` |
| `Y07`, `Y08`, `Y21`, `Y61` | `balance` |
| `X01`, `X02`, `X05`, `X08` | `revenue` |
| `X11`, `X12` | `expenditure` |
| `X21`, `X30`, `X42`, `X44`, `X47` | `balance` |

No first-letter allowlist can route those correctly, which is what the old
`flow_prefixes` architecture attempted.

### Two exclusions and one anomaly

- **`I--` (Total Interest On Debt) is excluded** — `is_aggregate = TRUE`,
  1967–2011, $1.72T. Mapping it alongside its own leaves would double-count
  interest into every total using it. Same treatment as `L--`.
- **`Q11` is an anomaly, mapped anyway.** A single FY1974 row of $181K reported
  by a **city** (type 2), though `Q` means state-to-school-district. Mapped to
  Education K-12 so no dollar-carrying code is left uncategorised; treat any
  `Q11` figure as suspect.
- **The summary-table QA artifacts exclude `interest`, `insurance_benefits` and
  `insurance_trust`** via `.drop_nonprimary()`. Those artifacts are a *primary
  direct expenditure + general revenue* view carried forward unchanged across
  vintages, so cross-vintage drift is the only signal in them. This does **not**
  limit readers: `summary_categories.parquet` publishes the CSV unfiltered.

## Cash and security holdings (`category_type = balance`)

`data/summary_categories.csv` carries a third `category_type` alongside
`revenue` and `expenditure`: **`balance`**, covering the 14 cash-and-security
holding codes (#76).

**These are stocks, not flows — do not sum them with money.** `E`/`F`/`G`/`T`
codes measure dollars moving over a fiscal year; these 14 measure a balance at
a single point in time. A stock/flow *ratio* is standard practice
(months-of-revenue-on-hand, reserve ratios); a stock/flow *sum* is meaningless.
The separate `category_type` is what makes the first reachable while keeping
the second out of both money verbs. Neither `cog_spending()` nor
`cog_revenue()` admits a `balance` row, and the pipeline's own summary-table QA
artifacts exclude them via `.drop_balance()` for the same reason.

### `balance_subtype`

Mirrors `spend_subtype` / `revenue_subtype`. `balance_subtype = 'general'` is
the one-filter answer to "give me fund balance".

| `balance_subtype` | codes | category | corpus years |
|---|---|---|---|
| `general` | `W01` Offsets to Debt (sinking funds), `W31` Bond Funds, `W61` All Other Funds | Fund Balances | 2012–2021 |
| `employee_retirement` | `X21` Cash & Short-Term, `X30` Federal Securities, `X42` Mortgages, `X44` Total Other Securities, `X47` Other Investments, `Z77` Corporate Bonds, `Z78` Corporate Stocks | Retirement System Holdings | 1967–2016 (varies) |
| `unemployment_trust` | `Y07` Balance in US Treasury, `Y08` Other Balance (may be negative) | Insurance Trust Balances | 1967–2023 |
| `workers_comp_trust` | `Y21` Cash and Assets | Insurance Trust Balances | 2012–2023 |
| `other_insurance_trust` | `Y61` Cash and Deposits | Insurance Trust Balances | 2012–2023 |

### Caveats you must surface to users

1. **Census holdings are NOT GAAP fund balance.** These are *gross* holdings
   with no liabilities netted. A reserve ratio built from them overstates what
   is actually available to spend.
2. **`W` is FY2012–2021 only** — ten years, stopping two years short of the
   corpus (absent FY2022–2023). A long fund-balance-share-of-revenue series is
   not available.
3. **The `X` family ends at FY2016**, when Census moved employee retirement to
   a separate survey.

### `X44` and `X35` are siblings, not parent and child

The 2006 manual calls `X44` a calculated statistic equal to
`X35 + Z70 + Z83 + Z84`, which reads like a double-count risk. It is not one in
this corpus, and **`X44` is deliberately NOT flagged `is_aggregate`**:

- The manual's own X44 Special Consideration 2 says state & local government
  securities were added to X44 *"effective with fiscal year 1988 data. Prior to
  that time, they were separately identified ... and coded at X35."*
- Corpus `X35` carries dollars **1967–1987** and is absent from 1988 onward —
  exactly the shape that ruling predicts. (`code_set` *expects* X35 through
  2011, but no data is ever present after 1987.)
- Measured 2026-07-30: of the 618 govid-years carrying both, `X35` **exceeds**
  `X44` in 7.8% (max ratio 81.7) — impossible if X44 contained X35.

So the two are disjoint pre-1988 and there is no overlap after. Summing them
for 1967–1987 is *correct*, which is what `SB181` already advises. `Z70`,
`Z83`, `Z84`, `X33`, `Z62` and `Z63` are absent from the corpus entirely, so no
other component of a calculated total overlaps its parent here.

### The `X40`/`X41` → `Z77`/`Z78` book-value → market-value break

Two separate changes that a naive series joins straight through:

| | change | year | catalogued as |
|---|---|---|---|
| **Identity** | `X40` → `Z77`, `X41` → `Z78` | Census vocabulary FY2002 | `SB155`/`SB156` (`renamed_to`), `SB140`/`SB141` (`renamed_from`) |
| **Basis** | book value (original cost) → market value | FY2002 | `SB195`/`SB196` (`precision_change`) |

The subtlety: **in this corpus the identity and the basis change do not
coincide.** The wide-era source has no `Z77`/`Z78` columns at all — only
`EmpR_CpBds` (`X40`) and `EmpR_CpStk` (`X41`) — so `X40`/`X41` keep carrying
dollars under the same label every year through **FY2011**, while their
valuation basis switches underneath at FY2002. `Z77`/`Z78` first appear at
**FY2012**, the wide→modern reader boundary, and the seam is bridged by
harmonization recipes `cash_securities_z77_wide` / `cash_securities_z78_wide`.

Consequences: a 1967–2011 `X40` series is continuous in *identity* but not in
*basis*, and the change is not detectable from the series alone — national
totals show no step at the switch (`$373.6M` FY2001 → `$347.6M` FY2002).
Flagged, not suppressed.

## Series breaks

The Census of Governments classification system changed materially at the following boundaries. Read [series_breaks.md](series_breaks.md) before designing any cross-boundary analysis.

| Boundary | Affected | Severity |
|---|---|---|
| **FY2005** | Hospitals (15), Debt (11), Coverage expansion (21), Selective sales tax (3), License tax (4), Other tax (2), Agriculture (10), State govt IG codes (2), Discontinued codes (6), New variables (13), E→J prefix (1) | **Major** |
| **FY1976/1977** | All derived (calculable) variables: ±1 rounding | Minor |
| **FY2002–2006** | All units: imputed records excluded | Minor |
| **FY2017** | Government ID format: 9-char → 12-char | Major (handled by `id_crosswalk.csv`) |

The FY2005 redesign is by far the largest break. Of the **196** catalogued
issues in `data/series_breaks.csv` (the authoritative source — these counts are
derived from it, not maintained by hand):

| Joinability | Count | Share |
|---|---|---|
| `yes` (freely joinable) | 7 | 4% |
| `with_caution` | 55 | 28% |
| `state_only` | 30 | 15% |
| `partial` | 12 | 6% |
| `no` (irreconcilable) | 92 | 47% |

## Validation gates

FY2012 is dual-sourced (legacy IndFin + modern Individual Unit file), which
makes it the pipeline's golden validation year for the ID crosswalks and the
wide→long pivot — see [`series_breaks.md`](series_breaks.md) § "The 2012
Collection Boundary". The `gate_2012` block in `config.yml`
(`cfg$gate_2012$g1_min` … `g5_min`)
configures five publish-blocking thresholds (G1–G5: government coverage,
classification completeness, amount agreement) computed by
`compute_2012_gate_metrics()` and asserted by `validate_2012_gate()`
(`R/gate_2012.R`). The check is wired into `_targets.R` as the
`validation_2012_gate` target, a required upstream of `publish_tree` — a
failing gate blocks publishing the corpus. For the full gate definitions,
current thresholds, and a mechanical debugging playbook for a wrong-looking
2013+ value, see [`2012_boundary_validation.md`](2012_boundary_validation.md).

## Coverage flags

The UserGuide [`02_variables.md`](userguide/02_variables.md) records which government types report each variable, in two eras (FY2004 and earlier; FY2005 and later). These flags are not currently joined into `wide_to_long_xwalk.csv` but are preserved in the rendered table. Open work — see [series_breaks.md](series_breaks.md#open-work) item 2.

## Long parquet columns (28-column schema v6, FIPS geography harmonization plan v2 Task 7)

The published corpus `data/long/year=YYYY/part-0.parquet` files contain 28
columns. Column order is authoritative. Schema v6 (2026-07-21) renamed
`fips_state_code`/`fips_county_code` to `fips_state_asof`/`fips_county_asof`
(same as-of-year meaning, clearer name) and inserted `cog_legacy_state`/
`cog_legacy_county` (cols 10–11) alongside them; `fips_state`/`fips_county`
(cols 1, 3) are now the **present/harmonized geography** (current county
identity carried back to every year, derived from `canonical_govid` —
`fips_state = substr(canonical_govid, 1, 2)`,
`fips_county = substr(canonical_govid, 4, 6)`), not the as-of-year value they
held under schema v5. `harmonized_code` and `survey_weight` (Phase R2) trail
`canonical_govid`. See also [reader-specification.md](reader-specification.md)
§ 3.

| # | Column | Type | Source | Notes |
|---|--------|------|--------|-------|
| 1 | fips_state | integer | Derived (`canonical_govid` cols 1–2) | **Present/harmonized** 2-digit FIPS state — the government's current geography, carried back to every year |
| 2 | type | integer | IndFin TypeCode / Individual Unit `type` | 0=State 1=County 2=Muni 3=Township 4=SplDist 5=ISD |
| 3 | fips_county | integer | Derived (`canonical_govid` cols 4–6) | **Present/harmonized** FIPS county code; 0/NA for states. Auto-handles renames/splits (e.g. Shannon→Oglala Lakota) with no per-county curation |
| 4 | govid | character | Individual Unit unit ID field | 6-char Census internal unit number |
| 5 | gov_blank | character | Individual Unit header | Reserved Census field; typically blank |
| 6 | gov_name | character | Individual Unit / IndFin Name | Government name |
| 7 | county_name | character | Individual Unit header | County name (may be blank for states) |
| 8 | fips_state_asof | integer | IndFin FIPS_State / Individual Unit as-of-year field | As-of-year FIPS state — the geography in effect that fiscal year (renamed from `fips_state_code` in schema v5) |
| 9 | fips_county_asof | integer | Legacy: `data/govs_fips_county_xwalk.csv` lookup on `(cog_legacy_state, cog_legacy_county)`. Modern: as-of-year field from source | As-of-year FIPS county code (renamed from `fips_county_code` in schema v5) |
| 10 | cog_legacy_state | integer | Legacy `StateCode`; GID-era `census_id` split | Original Census GOVS state code. Populated across the legacy + GID era (FY1967/1970–2016 in the published corpus); `NA` FY2017+ (PID era, no distinct GOVS code) |
| 11 | cog_legacy_county | integer | Legacy `County`; GID-era `census_id` split | Original Census GOVS county code. Populated across the legacy + GID era (FY1967/1970–2016 published); `NA` FY2017+ |
| 12 | fips_place_code | character | Individual Unit header | Place FIPS (cities/townships); blank otherwise |
| 13 | population | numeric | Individual Unit / IndFin Population | As-reported; see popyear |
| 14 | popyear | integer | Individual Unit header | Year of population estimate |
| 15 | enrollment | numeric | Individual Unit header | School enrollment (ISDs/schools only) |
| 16 | enrollyear | integer | Individual Unit header | Year of enrollment estimate |
| 17 | function_code | character | Individual Unit header | Census function classification code |
| 18 | sch_level_code | character | Individual Unit header | School level code (ISDs only) |
| 19 | fiscal_year_end | character | Individual Unit header | Fiscal year end date string |
| 20 | srvy_year | integer | File name / header | Survey year (= row's calendar year) |
| 21 | item_code | character | IndFin fin_code / Individual Unit item_code | Finance item code (e.g. T01, E62) |
| 22 | amt | numeric | IndFin amount / Individual Unit Amount | Dollar amount in **$1,000s** |
| 23 | srv_data | character | Individual Unit SrvData | Survey data flag |
| 24 | impute_flag | character | Individual Unit / IndFin Imputed | Imputation flag |
| 25 | is_aggregate | logical | Derived (wide_to_long_xwalk.csv) | TRUE if row is a Census subtotal aggregate |
| 26 | canonical_govid | character | Derived (`data/canonical_alias.parquet`) | Stable 12-char canonical ID (PID census_id frozen at FY2023 vintage; corpus-assigned `9xxxxx`-unit ids for governments never observed 2017+) |
| 27 | harmonized_code | character | Derived (`data/harmonization_map.csv`) | Cross-vintage comparable item code; `NA` on aggregate rows (harmonized space is leaf-only) |
| 28 | survey_weight | numeric | IndFin `Weight` (legacy years only) | Legacy sample-design metadata — see warning below. `NA` for every modern-source row (FY2013+ and the modern 2012 partition) |

**⚠ `survey_weight` is informational only — never aggregate with it.** The
Census Bureau's own documentation for the source files states it plainly:
*"The statistical weight (if provided) is for informational purposes only and
should not be used to derive any other statistics"* (`_ReadMe_First_IndFin.txt`),
and *"Do not use the weight field to derive state or national totals (or
county area totals)"* (`UserGuide.xls`, Data User Note 8). The column is
passed through faithfully from the source, which means it inherits the
source's four mutually incompatible encodings: a **reciprocal** scale for
1972–2000/2002/2004–2006 (`10000` = certainty, `0` = nonsample unit,
expansion factor = `10000/Weight` — so `200` means the unit stands for 50
governments), a **direct** scale in 2003 only (`Weight/10000`), a placeholder
`1` in 1967/1970/1971/1973/2001 (weights unavailable), and an unpopulated `0`
throughout 2007–2012. Multiplying `amt` by any single reading of this column
produces silently wrong totals (including exact zeros for 2007–2012). Its one
legitimate use is *sample-membership* classification in the reciprocal-scale
years: `Weight > 0` selects sample units, `Weight == 10000` certainty units.
Every pipeline aggregate ignores this column by design. Full evidence:
`.superpowers/sdd/weight-semantics-findings.md` (cog_pipeline repo).

**`canonical_govid` resolution (Phase P, superseding the Phase N/O 9-char design):**

Every government's `canonical_govid` is its **12-char PID-era census_id, frozen
at corpus vintage FY2023**, for its entire observed life in the corpus —
including years before FY2017, when it was still identified by a 9-char GOVS
ID or 14-char GID census_id. A government never observed 2017+ gets a
**corpus-assigned** 12-char id (`{fips_state:2}{type:1}{fips_county:3}{unit:6}`,
real geography, `unit` drawn from the reserved `9xxxxx` range) instead. The
full assignment rules, continuity table, and reserved-range headroom are in
`docs/ids_reference.md` § "Canonical namespace (Phase P)" in the
`cog_pipeline` repository, and the design rationale in
`docs/superpowers/specs/2026-07-10-phase-p-canonical-ids-design.md` there
(neither file ships with the published corpus).

**Opaque-key principle:** geography is never parsed out of `canonical_govid`.
ACS/GEOID joins always go through xwalk columns (`census_geoid` et al.) or
row-level FIPS codes, never by substring-slicing the canonical id. This
decouples the frozen identity from mutable geography — Census can (and does)
recode a government's embedded county/type digits across vintages without
ever changing its `canonical_govid`.

**Resolver — three exact alias lookups, no FIPS-key join at read time.** All
matching intelligence lives in the build-time alias table
(`R/canonical_ids.R` + `R/canonical_assembly.R`); the read-time resolver
(`.resolve_canonical_govid()` in `R/read_modern.R`, called from
`R/reshape.R::compute_long()` for the legacy era) is three lookups against
`data/canonical_alias.parquet`, keyed by era:

| Era | Source rows | `id_kind` | Lookup key |
|---|---|---|---|
| Legacy (IndFin ≤2012) | `R/reshape.R::compute_long()` | `legacy_9` | 9-char `legacy_id` |
| GID (2012–2016) | `R/read_modern.R::build_modern_long()` | `gid_14` | 14-char `census_id` |
| PID (2017+) | `R/read_modern.R::build_modern_long()` | `pid_12` | 12-char `census_id` |

A miss sentinels the row as `"LEG:{key}"` / `"GID:{key}"` / `"PID:{key}"`
rather than silently guessing — kept as a failure-visible mechanism, but
structurally near-impossible since the alias build ingests the same metadata
files the long build reads. **Sentinels are gated to zero in every published
partition**: `R/publish.R::write_long_year_partition()` runs a post-scope-
filter check (gate 1 of the validation suite, spec § 6) and `stop()`s the
build if any `LEG:`/`GID:`/`PID:` row remains.

## `population` and `popyear` (long schema cols 13–14)

These are population metadata columns from the F-33 fixed-width files. Census
uses them to compute the per-capita tables in its own COG publications.

- **Source bytes (modern era):** PID era (FY2017+) `population` cols 117-125,
  `popyear` cols 126-127 — see `R/read_modern.R::.read_pid()`. GID era
  (FY2012–2016) `population` cols 124-132, `popyear` cols 133-134 — see
  `R/read_modern.R::.read_gid()`.
- **Vintage:** `popyear` is a 2-digit year identifying which Population
  Estimates Program (PEP) value Census paired with that fiscal year. PEP
  estimates are sometimes lagged a year for fiscal-year alignment (e.g.,
  FY2018 paired with 2017 PEP).
- **Coverage:** Populated for gov types 0–3 (state, county, city, township).
  Masked to NA for gov types 4 (special districts) and 5 (school districts)
  in `R/read_modern.R::.apply_type_masks()`. Schools instead carry
  `enrollment` / `enrollyear`.
- **Relationship to PEP:** `population` is approximately the PEP estimate
  for `popyear` for that geography. It is *not* identical to a tidycensus
  `get_estimates()` pull because Census occasionally revises PEP
  retroactively while the F-33 value is frozen at publication.
- **Downstream use:** `uscogdata::cog_spending(per_capita = TRUE)` exposes
  this as the `census_f33` denominator via the `gov_population_yearly`
  view, joined on `(canonical_govid, year)`.

## Metadata parquets

### `data/canonical_fips_xwalk.parquet` — government master (Phase P)

One row per `canonical_govid`. Government types 0-3 only (v0.1 scope). Built
by `assemble_canonical_master()` (`R/canonical_assembly.R`) from the PID
universe (2017-23), the GOVS universe (2002-16), cross-era links (official
FIPS-key matches + curated continuations), and corpus-assigned fabrication
pins; enriched with ACS population via `data/external_id_xwalk.csv`. Master
count as of the current (v6) production: **40,330 governments** (38,817
`census_pid` + 1,513 `corpus_assigned`).

| Column | Type | Description |
|--------|------|-------------|
| canonical_govid | character | Stable 12-char canonical ID (see col-26 resolution above) |
| gov_name | character | Government name at latest observation |
| govs_type | integer | Government type (0-3 in v0.1) |
| type_label | character | Human-readable type label |
| fips_state | character | Zero-padded 2-digit FIPS state |
| fips_county | character | Zero-padded 3-digit FIPS county; `NA` for states |
| fips_place | character | Zero-padded 5-digit FIPS place/cousub code; `NA` for state/county |
| legacy_govs_id | character | 9-char GOVS legacy ID bridge for pre-2017 joins (IndFin archives, LILP); `NA` for governments born 2017+ |
| first_year | integer | First fiscal year observed in this corpus (clamped to the corpus's manifest year range) |
| last_year | integer | Last fiscal year observed in this corpus (clamped) |
| census_geoid | character | ACS GEOID at the pinned vintage. Construction branches by type: 0 = `SS`; 1 = `SS`+`CCC`; 2 = `SS`+`PPPPP` (place, sumlev 160); 3 = `SS`+`CCC`+`SSSSS` (county subdivision, sumlev 060) |
| population_acs | integer | ACS population estimate; `NA` when unresolved |
| pop_confidence | character | `exact` \| `unresolved` — describes only the ACS population match, not ID identity |
| id_source | character | `census_pid` (observed 2017+) \| `corpus_assigned` (fabricated for a pre-2017 death with no continuation) |

### `data/canonical_alias.parquet` — alias table (Phase P, new)

Many-to-one; **the resolver's only lookup** (see col-26 resolution above). One
row per `(alias_id, id_kind)` ever observed in source data. Alias count as of
Phase P production: **117,503 rows**.

| Column | Type | Description |
|--------|------|-------------|
| alias_id | character | The observed source-data ID (9, 12, or 14 chars, per `id_kind`) |
| id_kind | character | `legacy_9` \| `gid_14` \| `pid_12` |
| canonical_govid | character | The 12-char canonical this alias resolves to |
| match_method | character | `identity` (PID id = canonical) \| `crosswalk` (FIPS-key link, or a mid-era recoded `pid_12` variant — 187 in production) \| `continuation` (curated, see below) \| `fabricated` |

### Curation CSVs (Phase P, hand-touched, committed)

Three files drive cross-era linking (`R/canonical_curation.R`); all are
content-hashed `targets` file inputs (any edit invalidates the canonical
build). Production counts (current v6): **537 continuations / 53 rejections
/ 1,558 pins**.

#### `data/continuations.csv`

Curated rulings that a pre-2017 GOVS entity and a 2017+ PID entity are *the
same government* despite failing the automated FIPS-key match. Nothing enters
the alias table as `continuation` without appearing here.

| Column | Type | Description |
|--------|------|-------------|
| old_id | character | The pre-2017 id (9-char `legacy_9` or 14-char `gid_14`) |
| old_id_kind | character | `legacy_9` \| `gid_14` |
| canonical_govid | character | Canonical this entity continues into |
| gov_name | character | Government name (for audit readability) |
| reason | character | `form_change` \| `rename` \| `county_recode` \| `place_code_fix` |
| evidence | character | Free-text justification |

#### `data/continuation_rejections.csv`

Adjudicated *negatives* — candidate pairs reviewed and ruled genuinely
distinct governments. A rejection has no old→canonical mapping (it is the
opposite of a continuation), so it uses its own schema. Together with
`continuations.csv`, these let the fragmentation gate (gate 5) distinguish
"reviewed" from "not yet reviewed" high-confidence candidates.

| Column | Type | Description |
|--------|------|-------------|
| old_id | character | The pre-2017 id considered for continuation |
| rejected_canonical | character | The PID canonical it was proposed to (and did not) continue into |
| evidence | character | Free-text justification |

#### `data/corpus_assigned_ids.csv`

Fabrication pins for governments never observed 2017+. Minted once by
`scripts/mint_corpus_ids.R` and read thereafter — deterministic assignment +
a committed pin means IDs never shift across rebuilds. The `targets` build
fails loudly if a residual entity has no pin; it never mints silently. A pin
can also be superseded by a later-curated continuation (e.g. Shannon County
SD's pin, superseded by the Shannon→Oglala Lakota rename ruling); the pin
row stays committed and its unit number stays burned, which is why the
production file carries 1,558 pins but the master only 1,513 `corpus_assigned`
rows. The schema *permits* duplicate `canonical_govid` values as deliberate
**merge pins** — several `old_id`s (a GOVS-side recode chain) pinned to one
fabricated canonical, guarded at assembly time by geo+name agreement
(`assemble_canonical_master()` `stop()`s on disagreement). This mechanism
is exercised by the fixture corpus and unit tests (Russia City → Russia
Village is the fixture example); **the production file currently contains
zero duplicate canonicals** — the 9 production GID-alias collisions were
instead resolved by the embedded-owner dedup rule (see
`R/canonical_universe.R`).

| Column | Type | Description |
|--------|------|-------------|
| old_id | character | The dead pre-2017 id being fabricated a canonical for |
| old_id_kind | character | `legacy_9` \| `gid_14` |
| canonical_govid | character | The fabricated 12-char canonical (`9xxxxx` unit range) |
| gov_name | character | Government name |
| govs_type | integer | Government type (0-3) |
| fips_state | character | Zero-padded FIPS state |
| fips_county | character | Zero-padded FIPS county |

### `data/summary_categories.parquet`

Item code to category crosswalk. One row per item_code in scope.
See `data/summary_categories.csv` for source.

Columns: `item_code`, `category`, `category_type`, `spend_subtype`,
`revenue_subtype`, `balance_subtype`. `category_type` is one of `revenue`,
`expenditure` or `balance` — see
[Cash and security holdings](#cash-and-security-holdings-category_type--balance)
before using a `balance` row, which is a point-in-time stock and must never be
summed with a fiscal-year flow.

### `data/representation.parquet` and `data/code_set.parquet` — the absence rule

**Read this before concluding that a code disappeared.**

The corpus changes representation at FY2012, and an absent row means two
different things either side of that boundary:

| year | cell absent means | `absence_means` |
|---|---|---|
| **≤ FY2011** (`dense_source`) | Census published **$0** | `census_zero` |
| **≥ FY2012** (`sparse_source`) | **not reported** — unknown | `not_reported` |

The wide era's source rendering is *exactly dense*: every government carries a
row for every code in force, and 91.4% of those rows were explicit zeros — 226M
of what would otherwise be 253M corpus rows. The modern era emits only what a
government reports (FY2012 fill 9.2%). The published corpus therefore drops the
wide era's explicit zeros and states the rule instead.

**This is lossless.** Because the density is exact, every dropped zero is
reconstructible from three published artifacts, so traceability to how Census
originally reported is fully preserved without storing one of them:

- **`representation.parquet`** — one row per published year:
  `year`, `representation` (`dense_source` | `sparse_source`), `absence_means`,
  `code_set_id`.
- **`code_set.parquet`** — which codes were in force, per year **and government
  type**: `code_set_id`, `year`, `type`, `item_code`, `is_aggregate`,
  `n_units`. This is the piece a raw-parquet consumer cannot derive from the
  published corpus, and without it densification is wrong rather than merely
  incomplete: filling naively against the union of all types invents rows like
  "$0 state intergovernmental transfer to school districts" for counties and
  townships. The modern code set genuinely differs by type.
- **`canonical_fips_xwalk.parquet`** — the government universe (already
  published).

To densify a `dense_source` year: cross the year's governments with its
`code_set` rows for their `type`, left-join `long`, and set every unmatched
`amt` to `0`. The result is bit-for-bit what Census published. The pipeline
asserts exactly this round-trip on every build
(`tests/testthat/test-end-to-end.R`).

**Amounts are unaffected.** Every dropped row is exactly `$0`, so every sum,
total, ratio and per-capita figure is identical before and after. Only
*presence* changes — which is why no sum-based validation gate re-baselines.

**The trap this exists to close.** A code that "vanishes at FY2012" has almost
always just stopped having explicit zeros. Walkthrough finding F-006 reported
five categories losing every row at FY2012; all five carry rows through FY2023
(`E12`: 1,475 governments in 2012, 1,328 in 2022). Before reading any FY2012
disappearance as a retirement, **check whether the code still carries rows after
it.** Catalogued as `SB194`, so `cog_explain()` surfaces it.

> **Pipeline-internal frames stay dense.** Sparsification happens at the
> publish boundary only. `summarize_code_totals()` derives `n_units` (file
> membership — in a legacy year every code carries the identical unit count for
> its type, precisely *because* of the zeros) and `validate_unit_counts()`
> reads it. Sparsifying upstream would collapse `n_units` into
> `n_units_reporting` and gut that gate by construction. `code_set` is what
> gives the published corpus back the file-membership fact it drops.

## Lineage events (community contributions)

`canonical_govid` identity follows **Census's own filing lineage only** —
id-carrier / GID→PID seam continuations, curated in `continuations.csv`
above. That is a deliberately narrow policy: it answers "does Census's own
record-keeping treat this as the same government?", not "did this
government legally cease to exist and get absorbed by another?". The two
questions diverge for real-world consolidations, mergers, and annexations
that Census's own id lineage does not reflect (e.g. a city dissolves into a
county-consolidated government, or a small municipality is annexed by a
neighbor, but Census kept — or never carried — a distinct filing thread
linking the two ids). `data/lineage_events.csv` is where that second,
broader question is answered, as a separate, purely informational artifact.
See the full policy ruling in
[`phase_q_checkpoint.md`](phase_q_checkpoint.md) § 4.

### `data/lineage_events.csv`

| Column | Type | Description |
|--------|------|--------------|
| predecessor_canonical | character | 12-char `canonical_govid` of the government that ceased to file independently |
| successor_canonical | character | 12-char `canonical_govid` of the government it merged/annexed/consolidated into |
| event_year | integer | Calendar year the event took effect, in `[1900, 2100]` |
| relation | character | `merged_into` \| `annexed_by` \| `consolidated_into` |
| evidence | character | Free-text citation of a verifiable source |

**Relation semantics:**

- `merged_into` — the predecessor government legally merged with the
  successor (e.g. two cities combine under one charter).
- `annexed_by` — the predecessor's territory and population were annexed by
  the successor; the predecessor ceased to exist as an independent
  government.
- `consolidated_into` — a city-county (or similar) consolidation folded the
  predecessor into a unified successor government.

**Evidence expectations:** cite a source that another contributor could
independently verify — a state statute or municipal charter citation, a
Census Boundary and Annexation Survey (BAS) record, a contemporary news
report of the vote/effective date, or a state Secretary of State filing.
Bare assertions ("everyone knows X merged with Y") are not acceptable
evidence.

**Validation:** `read_lineage_events(path, master = NULL)`
(`R/canonical_curation.R`) is the validating reader, following the same
loud, row-numbered failure convention as the other curation-CSV readers in
that file (`.read_curation_csv` / `.assert_rows`). It checks: both canonical
columns are exactly 12 characters; `relation` is one of the three values
above; `event_year` parses to an integer in `[1900, 2100]`;
`(predecessor_canonical, successor_canonical)` pairs are unique; a
predecessor never equals its own successor; and — when a `master` tibble
(with a `canonical_govid` column) is supplied — every predecessor **and**
successor id actually exists in the corpus master. It is exercised directly
by the test suite (`tests/testthat/test-canonical_curation.R`) and wired
into the pipeline as the `validation_lineage` target in `_targets.R`, a
required upstream of `publish_tree` — so a malformed or unresolvable
contributed row fails the build loudly rather than shipping silently. The
validated file is published as `data/lineage_events.parquet` in the corpus
tree via the same `publish_metadata_parquet` conversion pattern used for
`summary_categories.parquet` above.

**Community contributions:** this file is hand-curated but deliberately
open to external PRs — add a new merger/annexation/consolidation as it's
identified, or correct/enrich an existing row as better evidence surfaces.
The validating reader is what makes that safe to accept: a contributed row
that doesn't parse, uses an unrecognized `relation`, or names a
`canonical_govid` outside the master fails the build immediately, by row
number, instead of silently corrupting downstream analysis.

**Never consumed by the resolver.** This is the single most important
property of this file: it is **not** joined into `canonical_alias.parquet`
and is **never** consulted by the read-time resolver
(`R/read_modern.R::.resolve_canonical_govid()` / `R/reshape.R::compute_long()`,
see the resolver description above). `canonical_govid` values in the
published long corpus are completely unaffected by what this file contains
— it is purely an analytical/informational cross-reference for downstream
consumers who want to reconstruct sum-of-parts continuity across a
consolidation (with the caveat, documented at point of use, that naively
summing predecessor + successor rows double-counts any overlapping years).

## Conventions

- **Dollar units:** All raw `amt` values from the legacy IndFin files are in **$1,000s**. The `cog_explorer` `R/04_adjust.R::adjust_inflation()` function converts to full real dollars. Pre-1977 values were originally in whole dollars then rounded to thousands; see series_breaks SB085.
- **Government type codes:** 0=State, 1=County, 2=Municipality, 3=Township, 4=Special District, 5=ISD/ESA, 6=Federal.
- **`census_id`:** width and namespace vary by vintage. **FY1967–FY2012 legacy IndFin** uses a 9-char GOVS ID. **FY2012–FY2016 Individual Unit files (GID era)** use a 14-char GOVS census_id (`{govs_state:2}{type:1}{govs_county:3}{unit:3}{00000:5}`). **FY2017+ Individual Unit files (PID era)** use a 12-char FIPS census_id (`{fips_state:2}{type:1}{fips_county:3}{unit:6}`). Phase C's `data/id_crosswalk.csv` reconciles legacy 9-char to modern 14-char (GID era) for cross-vintage joins. See [ids_reference.md](ids_reference.md) for the full layout tables of `Fin_GID_*`, `Fin_PID_*`, and `{YYYY}FinEstDAT_*_pu.txt`.
- **Item codes:** First letter is the spend/revenue type (E=Current Ops, F=Construction, T=Taxes, etc.); numeric suffix is the functional area (62=Police, 24=Fire, etc.). Note: `J` prefix introduced FY2005 for cash/assistance payments (was `E` for state/local, `I` for federal). **`M`**-prefix codes are **intergovernmental payments** *to local* governments
for that function and **`L`**-prefix codes are intergovernmental payments *to
state* governments; **`-NN`** codes are the per-function Direct **family
aggregates** (legacy era; e.g. `-05` = corrections Direct = `E05`+`F05`+`G05`). See ["Total spending": Direct, Total, and the M-code](#total-spending-direct-total-and-the-m-code) for how these combine and when to use each.
