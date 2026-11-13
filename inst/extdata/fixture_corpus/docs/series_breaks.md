# Series Breaks: Building a Continuous 1967–Present COG Time Series

> **Purpose.** Catalog every known boundary where Census of Governments
> finance series definitions change, so that downstream analyses can
> construct continuous 1967–present time series with explicit knowledge of
> what is joinable, what is conditionally joinable, and what is
> irreconcilable.
>
> **Audience.** Both human researchers and AI agents working with the
> long-format COG data produced by this pipeline. The companion machine-readable
> catalog is [`data/series_breaks.csv`](../data/series_breaks.csv) (**188 entries**
> as of the current v6 build; SB001–SB188); this document is the prose
> explanation and joining guide.

## TL;DR

| Era | Source | Coverage | Notes |
|-----|--------|----------|-------|
| 1967–2011 | `IndFin{yy}{a,b,c}.Txt` (this pipeline, Phases B–E) | All 553 stored variables in canonical SAS-position order | Pre-1977 in whole dollars; 2002–2006 excludes imputed records |
| 2012–present | Modern individual-unit files (`cog_explorer` `R/01_data.R`) | Long format with `item_code` + `amt` | Different ID scheme |

The **biggest single break** is FY2005, when Census implemented its largest classification revision in decades. Six categories of change land at FY2005:

1. **Hospitals** — own/other split eliminated; series irreconcilable without aggregation.
2. **Debt** — major restructuring; only 6 totals survive directly comparable.
3. **Selective sales / license / other taxes** — coverage expanded from state-only to all govts; pre-2005 residual codes (T19/T29/T99) are redefined.
4. **Agriculture** — function 54 codes discontinued for FY2005-2006, returned FY2007.
5. **State govt intergovernmental** — N codes (to general-purpose) and R codes (to special districts) collapsed into single M codes per function.
6. **Coverage expansion** — many state-only or jacket-unit-only codes expanded to all local governments; pre-2005 local time series for these codes begin in 2005.

Two smaller transparent changes also happen at 2005:

7. **E→J prefix** for cash/assistance payments (invisible at the `sas_var`/`sas_dbf` level — Census preserved both to avoid breaking SAS programs).
8. **2005 new variables** — 18 new variables added; most are aggregates back-populated to FY2004 and earlier.

Three other boundaries exist outside 2005:

- **1976/1977** — source files for FY1967–1976 were in whole dollars then rounded to thousands. Subtraction-based derivation formulas may produce ±1 spurious values across this boundary.
- **2002–2006** — historical IndFin files exclude records with imputed data; record counts won't match other published Census tables.
- **2017** — government ID scheme changes from 9-char GOVS IDs to 12-char IDs with FIPS county embedded. The `LILP` and `IDxWalk` crosswalks reconcile type=1 (counties); coverage of types 0/2/3/4/5 is uneven.

### Direct vs Total

Not a Census series break — a **corpus representation** choice, but it belongs in
the same "read before you aggregate" bucket. For each spending function Census
reports both a **Direct** amount (a government's own spending) and a **Total**
(Direct + the function's intergovernmental `M`- and `L`-code payments — to
local and state governments respectively). Before the v6 rebuild of
**2026-07-23**, both flavors were emitted under a *single* `item_code`,
so a consumer summing a family's aggregate rows silently double-counted. Since
that rebuild (the #28 "Option B" ruling) the corpus publishes **one flavor per
family — Direct** — and `Total` reconstructs as `Direct + M-code + L-code`
(both code families are published in both eras). Pre-2026-07-23 extracts carry both flavors under one code
and should be re-pulled. Full semantics and the query-shape rules (single-gov vs
cross-gov): [`data_dictionary.md`](data_dictionary.md#total-spending-direct-total-and-the-m-code) § "Total spending".

## How to Use This Catalog

### For human researchers

Read this document end-to-end before designing any cross-2005 analysis. For specific codes, query the CSV:

```r
sb <- readr::read_csv("data/series_breaks.csv")

# All breaks affecting a code
dplyr::filter(sb, fin_code == "T19" | grepl("T19", successor_codes) | grepl("T19", predecessor_codes))

# All irreconcilable breaks in a domain
dplyr::filter(sb, domain == "hospitals", joinable == "no")

# Codes safely joinable across 2005
dplyr::filter(sb, joinable == "yes")
```

### For AI agents

Before writing code that joins legacy (pre-2012) data with modern (2012+) data, **always**:
1. Load `data/series_breaks.csv`.
2. For each `fin_code` or `sas_dbf` in the analysis, look up its `joinable` flag.
3. If `joinable != "yes"`, surface the `join_advice` to the user before proceeding.
4. If the analysis crosses FY2005, FY1977, or FY2017, explicitly check those boundaries.

A test that asserts the count of `joinable = "yes"` rows is stable lives in `tests/testthat/test-series_breaks.R`.
5. Use `cog_code_info(item_codes)` from `R/reshape.R` to look up boundary class and join advice for any code.

### `joinable` enum

| Value | Meaning | Action |
|---|---|---|
| `yes` | Series definition stable across the break | Join freely. |
| `with_caution` | Definition stable but minor numerical issues (rounding, alternate codes) | Join, but document the caveat in any derived series. |
| `state_only` | Joinable across the break **only** for state governments. Local govt series begins at the break year. | Filter to state govts before joining; do not present local govt time series spanning the break. |
| `partial` | Series has gap years or returns in altered form | Hold the gap years as `NA`; document the gap in metadata. |
| `no` | Definition genuinely changed; joining would mislead | Do not join. Either present as two separate series, or use a documented aggregation rule (e.g. sum hospital own+other pre-2005 to compare to all-hospitals post-2005). |

## Domain-by-Domain

### Hospitals (FY2005, 15 entries)

**Pre-2005:** Census collected hospital finances under two functions:
- **Function 36 — "Own Hospitals":** hospitals administered/operated by the government itself
- **Function 38 — "Other Hospitals":** hospitals supported but not operated by the government

Each function had the full set of expenditure codes: `E36/F36/G36/K36/L36/M36` and `E38/F38/G38/K38/L38/M38`.

**Post-2005:** Census collapsed both functions into a single "Hospitals" series, all reported under function 36. Function 38 was eliminated as a distinct line. The IG-to-state and IG-to-local sub-series moved from L38/M38 to L36/M36.

**Joinability verdict for continuous 1967–present hospital series:**

| Series you want | Pre-2005 source | Post-2005 source | Method |
|---|---|---|---|
| Total hospital current ops | `E36 + E38` | `E36` | **Sum** legacy own+other to compare to modern function 36 |
| Total hospital construction | `F36 + F38` | `F36` | Sum legacy own+other |
| Total hospital IG to state | `L36 + L38` | `L36` | Sum legacy own+other |
| Total hospital IG to local | `M36 + M38` | `M36` | Sum legacy own+other |
| Hospitals operated directly by govt | `E36` | **unavailable** | Cannot construct post-2005 series |
| Hospitals supported but not operated | `E38` | **unavailable** | Cannot construct post-2005 series |

**Pre-built aggregates:** UserGuide added new aggregate codes `C580a` (Total Hospital Construction = F36+F38), `C589b` (Total Hospital IG to State = L36+L38), and `C589c` (Total Hospital IG to Local = M36+M38) at FY2005, back-populated to FY2004 and earlier. These can be used as the legacy half of the bridge directly.

**Equipment (K-codes):** Pre-2005, K36/K38 were collected for state govts and large local "jacket" units. Post-2005, K-codes are state-govt only. Local-govt K-code time series cannot extend across the boundary.

### Debt (FY2005, 11 entries)

**The largest single rewrite in the FY2005 redesign.** Census eliminated:
- Full-faith-and-credit vs nonguaranteed distinction
- Utility debt vs general government debt distinction
- All functional detail of debt (except public debt for private purposes)
- Offsets to debt

**Six debt totals survive directly comparable** across FY2005:

| sas_var | sas_dbf | Description |
|---|---|---|
| C1203 | TotDebtOS | Total debt outstanding at end of fiscal year |
| _64V | ST_DebtOS | Short-term debt outstanding at end of year |
| C1204 | LTDebtOS | Total long-term debt outstanding at end of year |
| C1221 | BegOS_Tot | Total long-term debt outstanding at beginning of year |
| C1232 | TotIss_Tot | Total long-term debt issued |
| C1401 | TotRet_Tot | Total long-term debt retired |

**Public debt for private purposes** uses new codes at FY2005 (`_49T`, `_19Ta`, `_29T`, `_39T`) to distinguish from old codes (`_19T`, etc.). The Census notes: *"In theory, new codes for 'public debt for private purposes' are not the same as prior years because the latter treated them as 'nonguaranteed' general debt, two categories that no longer exist. In reality, however, they are identical."* Joinable with caution.

**All other debt sub-categories are discontinued.** Don't attempt to construct guaranteed-vs-nonguaranteed or utility-vs-general-debt time series past FY2004.

### Selective Sales Taxes (FY2005, 3 entries)

| Code | Description | Pre-2005 coverage | Post-2005 coverage |
|---|---|---|---|
| T11 | Amusement tax | State govts only | All govts |
| T14 | Pari-mutuels tax | State govts only | All govts |
| T19 | Other selective sales tax | All govts (residual; **includes** local T11/T14 amounts) | All govts (residual; **excludes** local T11/T14 amounts) |

**State-govt time series for T11 and T14 are joinable across 2005** with no caveats. **Local-govt time series for T11 and T14 begin at FY2005** — there are no earlier values because they were folded into T19.

**T19 is not directly joinable across 2005 for any govt type** because its definition changed. To construct a continuous T19-equivalent residual:
- Pre-2005: Use raw T19 (it already includes local T11/T14)
- Post-2005: Use `T19 + (local-only T11) + (local-only T14)` to recreate the pre-2005 inclusion

### License Taxes (FY2005, 4 entries)

Identical pattern to selective sales taxes:

| Code | Description | Pre-2005 | Post-2005 |
|---|---|---|---|
| T21 | Amusement licenses | State only | All govts |
| T23 | Hunting and fishing licenses | State only | All govts |
| T27 | Public utility licenses | State only | All govts |
| T29 | Other licenses (residual) | Includes local T21/T23/T27 | Excludes local T21/T23/T27 |

Same joining advice as selective sales taxes.

### Other Taxes (FY2005, 2 entries)

| Code | Description | Pre-2005 | Post-2005 |
|---|---|---|---|
| T53 | Severance taxes | State only | All govts |
| T99 | Taxes NEC (residual) | Includes local T53 | Excludes local T53 |

Same pattern.

### Agriculture (Function 54, FY2005-2006 gap, 10 entries)

Agricultural codes were **discontinued for FY2005 and FY2006 only**, then **returned in FY2007** in their original form. During the gap, amounts were folded into function 59 (Natural Resources).

| Code | Description |
|---|---|
| B54 | Federal IG Revenue - Agriculture (gap → B59) |
| A54 | Charges - Agriculture (gap → A59) |
| E54, F54, G54, K54, L54, M54 | Agriculture function expenditures (gap → 59) |

**Side effect:** B59 and A59 absorb the agricultural amounts in FY2005 and FY2006, then drop them again in FY2007. **Both B59 and A59 have artificially elevated values for FY2005-2006** that should be flagged.

For continuous 1967–present agriculture series, the recommendation is:
- 1967–2004: Use `*54` directly
- 2005–2006: **NA** (or document the value as part of `*59`)
- 2007–present: Use `*54` directly again

### State Government Intergovernmental Payments (FY2005, 2 entries)

**Pre-2005:** State govt IG payments to local govts were broken down by *recipient govt type*:
- **N-codes (32 of them):** N01–N94 — payments to general-purpose local govts (counties, municipalities, townships)
- **R-codes (32 of them):** R01–R94 — payments to special districts
- **M-codes:** payments to school districts (and a few others)

**Post-2005:** All collapsed into a single M-code per function. Recipient-type detail eliminated.

**Joining advice:** For continuous 1967–present state IG time series, **sum N+R+M pre-2005** to approximate the post-2005 M total. Recipient-type detail (general purpose vs special district vs school) cannot be reconstructed for 2005+.

### Coverage Expansion (FY2005, 21 entries)

A large set of revenue and expenditure codes were collected only for state governments or "jacket" units (large cities/counties) before FY2005. Post-2005, these are collected for all local governments (except school districts in some cases).

| Code | Description |
|---|---|
| A60 | Charges - Parking Facilities |
| B01, B59 | Federal IG Revenue - Airports, Natural Resources |
| A03 | Charges - Misc Commercial Activities |
| A16, A18 | Charges - Higher Ed Auxiliary Enterprises, Other Higher Ed (combined in this database) |
| A36 | Charges - Public Hospitals |
| A45 | Charges - Toll Highways |
| A59 | Charges - Other Natural Resources |
| U01 | Misc Gen Rev - Special Assessments |
| U11 | Misc Gen Rev - Sale of Property (also absorbs U10) |
| U30 | Misc Gen Rev - Fines and Forfeits |
| U41 | Misc Gen Rev - Royalties |
| U50 | Misc Gen Rev - Donations from Private Sources |
| Function 60 | Parking Facilities expenditures |
| Function 03 | Misc Commercial Activities NEC |
| Functions 04, 05 | Corrections Institutions, Corrections NEC (combined in this database) |
| Function 16 | Higher Education Auxiliary Enterprises (combined with 18) |
| Function 45 | Toll Highways |
| Function 62 | Police Protection (some govt types) |

**Joining advice:** For state-government time series, these are joinable across FY2005 with no caveats. **For local-government time series, the values for these codes pre-2005 were folded into "all other" residual categories (B59, A89, U99, etc.).** A continuous local-govt time series therefore either:
- Begins at FY2005 (the natural starting point), or
- Uses the residual category for pre-2005 and the specific code post-2005, with explicit documentation that the pre-2005 segment is an upper bound.

### E→J Prefix Change (FY2005, transparent in this database)

Pre-2005, the expenditure prefix `E` was used both for current operations *and* for cash/assistance/subsidy payments (`I` for federal). At FY2005, Census introduced prefix `J` for all cash and assistance payments to disambiguate.

**This change is invisible at the `sas_var` and `sas_dbf` level** — Census preserved the SAS variable names and dBase labels to avoid breaking existing programs. Modern files use the `J` prefix in `fin_code`, but the underlying variable identity is the same.

**Joining advice:** Yes, joinable. When mapping legacy `E*` codes that represent assistance payments to modern `J*` codes, use the `sas_dbf` as the join key (it's stable) and treat `fin_code` as a presentation field.

### New Variables Added in FY2005 (13 entries)

The Census added 18 new variables at FY2005, most of which were back-populated to FY2004 and earlier. Notable ones already covered above:
- Hospital aggregates: `C580a`, `C589b`, `C589c`
- Debt aggregates: `_49T`, `_49U`, `_19Ta`, `_19U`, `_29T`, `_29U`, `_39T`, `_39U`, `C1204a`
- New tax codes: `T11`, `T14`, `T21`, `T23`, `T27`, `T53` (newly collected for all govts; covered above)
- New expenditure codes: `S74` (Medicare Part D state share, reclassified as `E73` in FY2007)
- Education/Highway/Welfare construction aggregates: `C410a`, `C607a`, `C820a`
- Duplicates added for query convenience: `C311a`, `I89a`, `E19a`

**The duplicates with same `sas_dbf` are the four cases handled in [`docs/archive/reconciliation_task.md`](archive/reconciliation_task.md):** `OthHos_IGS`, `OthHos_IGL`, `GenIntExp`, `BegOS_PDPP`. The pipeline disambiguates the second occurrence with a `__{sas_var}` suffix.

### Discontinued Codes (FY2005, 6 entries)

Codes that ended at FY2005 with no successor in the modern data:

| Code | Description | Successor |
|---|---|---|
| L24 | Fire Protection IG to State Govt | None — discontinued |
| E47 | Direct subsidies to private transit companies | E89 (Transit Subsidies, NEC) |
| Z61 | Contribution to Government's Own Transit System | None — exhibit code discontinued |
| L50 | Housing & Community Development IG to State | None — collected only in FY2005 |
| J85 / E84 | State govt veteran cash bonuses | None — collected only in FY2005 |
| U10 | Sale of Property - Housing & Community Development | U11 (absorbs it) |

**Joining advice:** Time series for these codes terminate at FY2004 (or FY2005 for the one-year-only entries). For E47→E89 and U10→U11, the modern code captures the legacy concept; concatenate explicitly.

### Pre-1977 Dollar Precision (1976/1977, 1 entry)

Source files for fiscal years 1967–1976 were in **whole dollars** at the time of collection, then rounded to thousands when assembled into the IndFin database. Source files for FY1977 and later were already in thousands.

**Effect:** Subtraction-based derivation formulas (most of the 135 entries in `data/wide_derived_formulas.csv`) may produce **±1 spurious values** for FY1967–1976 due to compounding rounding error. This is a Census-acknowledged caveat (see [`docs/userguide/07_formulas.md`](userguide/07_formulas.md)).

**Joining advice:** Treat all derived (`is_derived = TRUE`) values for FY1967–1976 as having implicit precision of ±1 thousand. Do not present derived values for these years to more than 3-4 significant figures. Stored values are unaffected.

### Imputation Exclusion (FY2002-2006, 1 entry)

Records with imputed data are **excluded** from the historical IndFin files for fiscal years 2002–2006. Record counts will not match other published Census tables for these years (e.g., the official Census of Governments publications).

**Joining advice:** When constructing govt-level time series, do not interpret missing records in 2002–2006 as govt closure or merger; the unit may simply have been imputed and therefore excluded. Cross-reference against `ALLids.csv` or the modern Census of Governments unit lists to distinguish.

### Government ID Scheme Change (FY2017, 1 entry)

| Era | ID format | Length | Components |
|---|---|---|---|
| Pre-2017 | GOVS ID | 9 chars | state(2) + type(1) + govid(6) |
| Post-2017 | Census ID | 12 chars | fips_state(2) + type(1) + fips_county(3) + govid(6) |

**Reconciliation status:**
- **Type 1 (counties):** LILP crosswalk + IDxWalk reconcile pre/post-2017 IDs cleanly.
- **Types 0, 2, 3, 4, 5:** Coverage is uneven. The `id_xwalk` target in this pipeline emits coverage stats; downstream code should respect the `source` and `confidence` columns.

See `data/id_crosswalk.csv` (built by `tar_make()` from `IDxWalk.Txt`, `ALLids.csv`, and `PID_GID_Crosswalk_LILP.csv`).

### FIPS 66 (Guam) Historic Inconsistency

Pre-2000-ish data sometimes uses FIPS 66 inconsistently. The `cog_explorer` `R/03_lookup.R` `fips_to_stabbr()` function correctly maps FIPS 66 → GU (not GA, which uses FIPS 13). Documented in [`CLAUDE.md`](../../CLAUDE.md).

## Counts (April 2026)

Verified against [`data/series_breaks.csv`](../data/series_breaks.csv):

| Joinability | Count | Share |
|---|---|---|
| `yes` (freely joinable) | 7 | 8% |
| `with_caution` | 17 | 19% |
| `state_only` | 28 | 32% |
| `partial` | 8 | 9% |
| `no` (irreconcilable) | 28 | 32% |
| **Total** | **88** | |

**By domain:**

| Domain | Count |
|---|---|
| Coverage expansion | 21 |
| Hospitals | 15 |
| Debt | 11 |
| Agriculture | 10 |
| New variables (2005) | 7 |
| Discontinued | 6 |
| License taxes | 4 |
| Selective sales taxes | 3 |
| Other taxes | 2 |
| State govt IG (N/R codes) | 2 |
| New taxes (2005) | 2 |
| Precision change (1976/77) | 1 |
| ID scheme change (2017) | 1 |
| Imputation exclusion (2002–2006) | 1 |
| Reference (FIPS 66) | 1 |
| E→J prefix change | 1 |

## The 2012 Collection Boundary (Wave 4 — April 2026)

The 2012 fiscal year is the **only year** with data in both the legacy wide-format
IndFin files (1967–2012) and the modern Individual Unit files (2012–present). This
makes it the empirical test point for reconciling the two formats.

### Audit findings

A full boundary audit ([`data/boundary_2012_audit.csv`](../data/boundary_2012_audit.csv), 502 codes)
classifies every item code that appears in either format:

| Boundary class | Count | Description |
|---|---|---|
| `atomic_both` | 267 | Code in both formats; directly comparable |
| `atomic_modern_only` | 59 | Code exists only in the modern file (new FY2002/2005) |
| `atomic_wide_only` | 19 | Code exists only in the legacy wide format (no modern equivalent) |
| `wide_aggregate` | 95 | Subtotal/aggregate in wide format (excluded from pivot) |
| `wide_subtype` | 62 | Pre-2005 letter-suffixed sub-function codes (all zero in 2012) |

### Dash-suffix aggregates

86 wide-format item codes contain a dash character (e.g. `T--` = total taxes, `-24` = total fire protection). These are logical aggregates of atomic codes — the modern file reports only the atomic components. All 86 are now correctly flagged `is_aggregate = TRUE` in [`data/wide_to_long_xwalk.csv`](../data/wide_to_long_xwalk.csv) and excluded from the pivot.

### Modern-only codes (53 new series_breaks entries: SB089–SB141)

59 codes appear in the modern 2012 file but not in the legacy wide xwalk. They fall into families:

- **IGR sub-codes** (B91-B94, C91-C94, D91-D94): Federal/State/Local intergovernmental revenue "Other" and "Transit" sub-codes split from parent codes (B89/C89/D89, B47/C47/D47) at FY2005.
- **IGE sub-codes** (L91-L94, M91-M94): Same split pattern for intergovernmental expenditure.
- **Function 04** (E04, F04, G04, L04, M04): Judicial/Legal split from Corrections (function 05) at FY2005.
- **Higher Ed** (E16, F16, G16): Auxiliary enterprises detail, new FY2005.
- **Function 85** (E85, F85, G85): Miscellaneous commercial activities, new FY2005.
- **Water utility** (W01, W31, W61): Water supply detail codes, new in modern file.
- **Welfare vendor** (J67, J68): Cash/assistance vendor payments using new J prefix, FY2005.
- **Pension** (Q12, Q18): Employee retirement contributions by education level, FY2005.
- **Retirement** (X02, X30, Y11-Y61): Employee retirement system detail codes, FY2002.
- **Cash/securities** (Z77, Z78): Market-value corporate bonds/stocks replacing X40/X41, FY2002.

### Wide-only parent codes (20 new series_breaks entries: SB142–SB161)

20 legacy codes are now catalogued as predecessors to modern sub-codes:
- B89→B91/B92/B93, C89→C91/C92/C93, D89→D91/D92/D93 (IGR "Other" splits)
- B47→B94, C47→C94, D47→D94, L47→L94, M47→M94 (Transit renames)
- E05→E04+E05, F05→F04+F05, G05→G04+G05, M05→M04+M05 (Corrections split)
- E67→E67+J67, E68→E68+J68 (Welfare vendor split)
- X40→Z77, X41→Z78 (Book value → market value)
- U4-→U40+U41 (Rents/Royalties split)

### Gate T5 reconciliation metrics (VT+WY fixture, full 2012 data)

| Metric | Pre-Wave4 | Post-Wave4 |
|---|---|---|
| Shared-pairs match rate | 97.50% | **98.51%** |
| Legacy-only rows | ~800K | **3,153** |
| Modern-only rows | ~576K | **719,211** (now classified as `format_modern_new`) |
| Discrepancy rows | ~29K | **15,134** |
| Unclassified | N/A | **0** |

### Corrections national-aggregate scope difference (2011/2012)

The pipeline's Phase M aggregate fallback uses the Census dash-prefix `-05` aggregate
for Corrections in legacy years (FY2005–2011). That aggregate was Census-precomputed as
"Total Corrections for this government unit" and includes **all** spending types for
function 05: direct operations (E05), construction (F05), other capital (G05), equipment
(K05), **and intergovernmental outflows** (L05 = IG to state, M05 = IG to local govts).

When this is summed across all government units at the national level, the
state→county IG transfer for corrections is **double-counted**: it appears in the
sending state's `-05` aggregate as L05 and again in the receiving county's `-05` as
its own E05 spending. Modern leaf-code years (FY2012+) use only
`E04+E05+F04+F05+G04+G05` — direct operations and capital, with no IG flows — so
the double-count does not occur.

**Practical consequence:** A national Corrections time series will show a visible step
down at 2012. In the FY2005–2011 range the published total is on the order of **$120–150B**;
FY2012+ is roughly **$70–95B**. The FY2010 BJS Justice Expenditure estimate (state + local,
direct expenditure only) was approximately $80B — consistent with the modern series, not
the legacy one.

| Scope | Pre-2012 value | Post-2012 value | Joinable? |
|-------|----------------|-----------------|-----------|
| National total | ~$120–150B (inflated) | ~$70–95B (direct only) | `no` — do not join |
| Single government | OK (no double-count at unit level) | OK | `with_caution` |

**Recommended description for analyses spanning 2005–2012:**

> "Corrections spending figures for years 2005–2011 are derived from the Census of
> Governments IndFin legacy aggregate, which includes intergovernmental transfers
> sent to other governments for corrections purposes. National totals before 2012
> may be roughly 1.5–2× larger than comparable post-2012 figures due to this
> double-counting of state→local transfers. Individual-government comparisons are
> not affected. The 2012 boundary marks a change in both source format and
> expenditure scope."

**In `explore_aggregates.R`:** The `used_agg` flag in `national_by_year` marks which
years use the legacy aggregate. Charts render these with open-circle points and dashed
lines, and a format-change annotation at the 2011/2012 boundary.

### Using `cog_code_info()`

```r
source("R/reshape.R")
cog_code_info(c("T01", "B89", "W61", "Z77"))
# Returns boundary_class, joinable, break_year, join_advice, description
```

### 2012 dual-source revision-vintage residuals

The Q2→Q3 checkpoint (`docs/phase_q_checkpoint.md` § 2, ruling 2026-07-12)
reviewed the residual gap between the legacy IndFin extract and the modern
Individual Unit file for FY2012 and accepted four defect classes as
document-only (none require a crosswalk fix). The full debugging playbook —
how to trace a specific wrong-looking code back to one of these classes —
lives in [`2012_boundary_validation.md`](2012_boundary_validation.md).

**Class C — G5 discrepancies (revision-vintage amount differences).**
**14,311 discrepancy pairs of 950,415 shared pairs**, within-tolerance rate
**98.62%**. A `discrepancy` status (`\|delta\| > tol`) on a shared
`(census_id, item_code)` pair does not by itself mean the pipeline mis-joined
or mis-derived a value — the legacy IndFin extract and the modern Individual
Unit file are two independently-timed Census-internal snapshots of the same
underlying FY2012 survey response. Census revises unit-level data between
when the IndFin extract is frozen and when the Individual Unit file is
published, so a shared pair can legitimately carry two different amounts
for the same code and government. Ruling: **accepted 2026-07-12** at the Q2→Q3
checkpoint (`docs/phase_q_checkpoint.md` § 2, class C) as an inherent
property of comparing two revision vintages, not a fixable defect. The
`G5` gate's threshold (`cfg$gate_2012$g5_min`) is set to accommodate this
residual rather than to drive it to zero — see
[`2012_boundary_validation.md`](2012_boundary_validation.md) § 2 for the
current threshold values.

The other three checkpoint-accepted classes are government-coverage or
per-pair-asymmetry residuals rather than amount discrepancies; see
[`2012_boundary_validation.md`](2012_boundary_validation.md) § 4 for the
full writeup of each:

- **Class A** — G1 misses, post-2007 incorporations absent from the legacy
  extract (139 governments; [`data/phase_q_2012_g1_misses.csv`](../data/phase_q_2012_g1_misses.csv)).
- **Class B** — G2 misses, boundary deaths pinned to corpus-assigned
  `9xxxxx` canonical IDs (6 governments; [`data/phase_q_2012_g2_misses.csv`](../data/phase_q_2012_g2_misses.csv)).
- **Class D** — `*_only_atomic` pair asymmetries, Wave-4-accepted
  (7,714 modern-only-atomic + 1,284 legacy-only-atomic pairs).

### Phase R2 inventory additions (SB162–SB163)

The Phase R2 harmonization inventory (published-corpus measurement,
`scripts/build_harmonization_inventory.R`) surfaced two leaf codes whose
nonzero data ends at FY2006 with no catalog entry: **X04** (`EmpR_LocLo`,
local employee-retirement intragovernmental contribution to local system)
and **X06** (`EmpR_StaSt`, state contribution to own system). Both are
catalogued as `discontinued` / `joinable = no` with `break_year = 2007` and
ruled `discontinued_na` in `data/harmonization_map.csv`. Catalog is now 163
entries. Related observation (documented, not yet catalogued): Z77/Z78 and
X02/X30 go zero after FY2016 (PID-era reporting change) — see
`docs/phase_r_harmonization_review.md` § 2.

## The Phase R3 Wave (SB164–SB188, July 2026)

Twenty-four entries added 2026-07-20, every one sourced to a primary document
or a reproducible measurement (evidence chain:
`.superpowers/sdd/weight-semantics-findings.md`, `blockers-final-23.md`,
`wave5-brief.md` in the pipeline working tree; commit messages `00b4275`,
`2cb4980`, `cdd5350`, `5a37f01`, `a2a6b38`). Highlights by boundary:

- **FY1982 internal-database restructure** — `SB169`: state education
  IG-to-locals relocated M21 → 44T (a code that does not exist before 1982;
  −$56.0B/+$61.7B measured offset). `SB184–SB187`: the local-scope
  education-NEC family (E21/F21/G21/L21, trivial amounts) explicit-NA'd.
- **FY1988** — `SB181`: X35 folded into X44, documented in the wide xwalk in
  both directions, measured exactly zero from 1988. `SB182/SB183`: General
  Revenue Sharing (B27, $68B, statutory end 30-Sep-1986) and state tax
  relief (C28, $22B) end with no successor — catalogued `discontinued`,
  mapped `discontinued_na` (an identity mapping was approved and then
  rejected by the harmonization namespace gate: dead codes cannot enter the
  FY2023-vintage namespace; the S74 precedent).
- **FY1996–2001 CUNY compilation gap** — `SB179/SB180`: Census stopped
  compiling CUNY community-college operations into NYC's record (E18 city
  $488.8M → $2.9M) while NYC's audited CAFRs carried ~$650–670M/yr
  continuously, then restored coverage at the 2002 CoG. Census's published
  classification never changed across the 1992–2012 Individual State
  Descriptions. Neither the exclusion nor the correction was announced.
- **FY2005 expansions missed by Wave 4** — `SB164/SB165`: T51 (documentary &
  stock transfer tax, 1→293 city reporters) and E77 (welfare institutions,
  6→194 county reporters).
- **FY2012 format boundary** — `SB166/SB167`: Y04 and M18 largely absent
  from the modern source for states ($22.2B/$8.7B legacy-only in the T5
  decomposition). `SB168`: the G94/F94 construction-vs-other-capital split
  is drawn differently between products (NYC carries E94 identical to the
  dollar in both; G94 −$3.08B offset by F94 +$2.05B) — sum F94+G94 across
  2012.
- **FY2017 (undocumented)** — `SB177/SB178`: the central-collection channel
  begins coding California county CalWORKs cash aid under J68 instead of
  J67 (CA-only; contradicts the classification manual; LA County continuous
  under the new code). No published Census documentation exists.
- **FY2022 reorganization (documented)** — `SB170–SB176`: E74/E75 and
  J67/J68 merged into E79, S67 into S89, per the *2022 State Government
  Finances Technical Documentation* pp. 4–5 and the ASFIN item-code list
  (109 codes marked "DISCONTINUED as of 2022"). **This boundary is much
  larger than these seven entries** — all G- and K-codes collapse into
  redefined F-codes, W01/W31/W61 are dropped, conduit-debt T-codes are
  eliminated, and the social-insurance trust treatment change produces (in
  Census's own words) "a one-time series break for most expenditure
  categories." Full cataloguing is commissioned as Wave 5
  (`.superpowers/sdd/wave5-brief.md`).

**Companion catalog:** [`data/known_events.csv`](../data/known_events.csv)
(KE001–KE021) now records **real-world events** that legitimately move a
series — recessions, ARPA SLFRF, COVID hospital aid, the Tax Reform Act of
1986, the Big Dig wind-down, CA/TX recession cash-flow borrowing. It is
deliberately separate from this catalog: a known event leaves the series
fully joinable, whereas rows here document definitional changes. The
pipeline's cliff gate (`R/validate_series.R::validate_cliff()`) consumes
both, plus a reporter-based coverage-transition exclusion.

> **`volatile_codes` retired (v6).** The cliff gate's earlier per-code
> escape-hatch list (`cfg$cliff_gate$volatile_codes`) is now **empty (`[]`)** in
> both config profiles. The specific cliffs it used to wave through are instead
> dispositioned by ruling as `known_events.csv` entries (the KE014–021 wave),
> so every excused cliff now carries a documented real-world cause rather than a
> bare code on a suppression list. The `volatile_codes` threshold fields remain
> in `config.yml` only as an empty, inert hook.

**Validation state (2026-07-21):** `validation_harmonization` green over all
56 built years (map 92 rows, catalog **188**); test suite
`1819 PASS / 0 FAIL / 0 WARN / 4 SKIP`.

**SB188 (Jared ruling R3-C track, 2026-07-21)** — `M81` / FY2014,
`split_from` `E81`, `joinable = partial`. California reclassified solid-waste
management from state current operations to intergovernmental-to-local:
measured `E81` −$1,234.1M against `M81` +$1,217.6M (1.3% magnitude match), with
the function-81 parent total continuous ($1,532.7M → $1,514.7M, −1.2%) and the
new split persisting ten years. National `M81`/type-0 |log ratio| 2.068 at
2013→2014 is 3.9× the next-largest movement in a 32-year series. Keyed on `M81`
rather than the falling `E81` because `.exclude_catalogued_cliffs()` joins
`fin_code → harmonized_code`, so a row keyed on `E81` would grant no relief.

Of the 12 cliff-gate residuals, 6 are now dispositioned by ruling
(M81/2014 → SB188; M23/2014+2015 → KE012/KE013; G85/2017 → the scoped
`moderate_max_log_ratio`; M80/2022 → not a real cliff, a superseded-vintage
question). M32/2000 remains **unexplained** with no catalog row written, by
ruling — its cause is not established and encoding it as explained would be a
claim not earned.

## Cash-and-security holdings: the book→market basis break (SB195–SB196, July 2026)

Added with the `category_type = 'balance'` work (issue #76). The identity
change was already catalogued; the **basis** change was not, and the two do not
happen in the same place in this corpus.

**What Census did.** At survey year 2002 it began reporting corporate bonds and
stocks held by public employee retirement systems at *market* value rather than
*book* value (original cost), and moved them from `X40`/`X41` to `Z77`/`Z78`.
The 2006 manual is explicit: *"Prior to 2002, corporate bonds were reported at
book value ... The code used for that category was X40."*

**What this corpus shows.** The wide-era source has no `Z77`/`Z78` columns at
all — only `EmpR_CpBds` (`X40`) and `EmpR_CpStk` (`X41`). So `X40`/`X41` keep
carrying dollars under the same label **every year through FY2011**, and
`Z77`/`Z78` first appear at **FY2012**, the wide→modern reader boundary. The
seam is bridged by harmonization recipes `cash_securities_z77_wide` /
`cash_securities_z78_wide`, which already use 1967–2011 / 2012–2023.

So the two changes separate:

| | year | rows |
|---|---|---|
| Identity (`X40`→`Z77`, `X41`→`Z78`), as Census classification | FY2002 | `SB155`/`SB156`, `SB140`/`SB141` |
| Basis (book → market), **inside** the surviving `X40`/`X41` series | FY2002 | `SB195`/`SB196` |
| Code label actually changes **in this corpus** | FY2012 | harmonization recipes above |

`SB195`/`SB196` are `precision_change` / `with_caution`, matching `SB085` —
the one other precision_change in the file. They are deliberately **not**
`joinable = "no"`: there is no successor code pair to bridge, so a `"no"`
would oblige a harmonization map row for a break that has nothing to map.

**Why it matters and why it is invisible.** A 1967–2011 `X40` series is
continuous in identity but not in basis, and the switch cannot be detected from
the series itself — national totals show no step across it (`$373.6M` FY2001 →
`$347.6M` FY2002; `X41` `$757.6M` → `$802.7M`). Flagged, not suppressed.

## Employee retirement leaves the finance file at FY2016 (SB197–SB209, July–August 2026)

Added with the revenue-concept work (uscogdata#12), which is what first makes
these codes reader-facing. Nothing in the catalog recorded this cliff before.

**What Census did.** Government-administered employee retirement systems stopped
being carried in the annual finance file after FY2016; they are collected in the
separate Annual Survey of Public Pensions. The whole `X` family — flows and
holdings alike, plus `Z77`/`Z78` — carries dollars 1967–2016 and is simply
absent from FY2017 on.

**Why it matters now.** `X11`/`X12` sit **inside Census's Direct Expenditure**
(the manual's X11/X12 function page lists its coding options as *"Direct
Expenditure: X11 Benefit Payments, X12 Withdrawals / Intergovernmental
Expenditure: None"*), and `X01`/`X02`/`X05`/`X08` sit inside Insurance Trust
Revenue. So from uscogdata#12 onward, any `direct` or `total` expenditure series
and any `total` revenue series **steps down at the FY2016/FY2017 seam** by the
entire employee-retirement leg — $4.14B for Wisconsin state in FY2012 alone,
21.2% of its Direct. That step is a collection-scope change, not a real one.

| | years | rows |
|---|---|---|
| `X` flows carry dollars | 1967–2016 | — |
| `X`/`Z` holdings carry dollars | 1967–2016 | — |
| Collection moves to the pension survey — flows | FY2017 | `SB197`–`SB202` |
| Collection moves to the pension survey — holdings | FY2017 | `SB203`–`SB209` |

**The holdings half, added August 2026 (`SB203`–`SB209`).** This section always
described the termination as covering the whole `X` family, "flows and holdings
alike, plus `Z77`/`Z78`" — but only the six flow codes were catalogued.
`X21`/`X30`/`X42`/`X44`/`X47`/`Z77`/`Z78` had no entry, so a holdings series got
no signpost at the seam and `cog_explain()` said nothing. `uscogdata#25` made
those codes reader-facing through `cog_balances()`, which is what turned the gap
from latent into user-visible.

Measured corpus-wide before cataloguing, census-to-census so the sample cycle
cannot manufacture the result: **2,267** governments report holdings at FY2012,
**zero** at FY2017, and **zero** at FY2022, against a corpus that still carries
~38,000 governments in each of those years (38,948 / 38,681 / 38,316). The
termination is total and national — no code carries a single row after FY2016 —
rather than a coverage dip in one state or one government type.

**Why `coverage_restricted` and not `discontinued`.** The codes' identity never
changes: they mean exactly the same thing on both sides and simply stop being
collected in *this* file. There is no successor code, so there is nothing to
bridge. They are deliberately **not** `joinable = "no"` — that would oblige a
harmonization map row, and the only row that could exist (`discontinued_na`, as
`SB162`/`SB163` use for `X04`/`X06`) sets `harmonized_code` to `NA`, which would
drop these codes out of the harmonized basis entirely and silently remove
employee-retirement benefits from `direct` spending under the reader's
**default** basis. Same reasoning as `SB194`–`SB196`. Verified against the gate
in `R/harmonization.R`, which keys on `joinable == "no"`.

### `X44`/`X35` — checked and NOT catalogued as an overlap

Issue #76 proposed flagging `X44` `is_aggregate = TRUE` because the manual
defines it as `X35 + Z70 + Z83 + Z84`. Measured and rejected: the manual's own
X44 Special Consideration 2 dates the folding of state & local securities into
X44 to **FY1988**, corpus `X35` carries dollars only 1967–1987, and of the 618
govid-years carrying both, `X35` *exceeds* `X44` in 7.8% — impossible for a
parent/child pair. They are disjoint siblings, already correctly catalogued by
`SB181`, whose join advice ("sum with X44 pre-1988") is the right instruction.
No aggregate flag was added. See
[data_dictionary.md](data_dictionary.md#x44-and-x35-are-siblings-not-parent-and-child).

## Patterns that are NOT series breaks (Madison walkthrough, issue #61)

An audit of one government (Madison, WI) proposed seven code-level breaks.
**Five did not survive a corpus-wide check.** They are documented here rather
than in `series_breaks.csv` because each is real in the government where it was
observed but is *not* a property of the code — and an entry in that file fires
for **every** consumer of the code through `cog_explain()`. Writing them would
put a false statement in front of every user.

This section exists so the next person who hits one of these has the
measurement, and does not re-propose it. Assertions live in
`tests/testthat/test-vintage-series-breaks.R`
(`"government-specific patterns are NOT catalogued as code-level breaks"`).

### Two rules this section is really about

1. **A per-government change is not a code-level break.** Fiscal-dependency
   reclassifications, annexations and local accounting choices move one
   government's series without touching anyone else's.
2. **The census/sample cycle confounds every national comparison.** Years
   ending in 2 and 7 are full censuses (~39,000 governments); other years are
   samples (as few as ~6,400). Comparing a census year against a sample year
   manufactures a break that is not there. **Compare census-to-census or
   sample-to-sample.**

### F-005 — city K-12 education "vanishing" at FY1983

Madison's Education K-12 spending runs to $80.2M in FY1982 (43.6% of its
total) and **$0 in every year from FY1983**. Nationally, type-2 governments'
K-12 total *rises* straight through that boundary:

| year | nonzero type-2 govts | total ($1,000s) |
|---:|---:|---:|
| 1981 | 796 | 8,843,773 |
| 1982 | 745 | 8,942,471 |
| **1983** | **659** | **9,206,489** |
| 1984 | 695 | 9,983,183 |

**What actually happened:** Madison's school system became fiscally
independent, so its K-12 spending moved to a separate school-district
government (type 5) and out of the city's own record. A per-government
reclassification. Cataloguing `E12 @1983` would warn every user of `E12` about
something that happened to one city.

**If you hit this:** check whether the government has a fiscally independent
school district. City-level K-12 spending exists only where the school system
is a dependent agency of the city.

### F-009 (partly) — E59 and E87 at FY1982–83

Only `E25` (Judicial & Legal) has a real national step here — catalogued as
`SB190` (FY1977, first collection) and `SB191` (FY1982, 194 → 8,452 nonzero
governments). Its two companions do not:

| code | 1981 | 1982 | 1983 |
|---|---:|---:|---:|
| E59 (Natural Resources) | 2,388 | 2,941 | 2,534 |
| E87 (Other Transportation) | 113 | 134 | 130 |

Both grow smoothly. The FY1982/83 movement seen in one city is that city's own.

### F-010 — the Highways FY1972 "operations collapse"

An operations-only drill-down shows Madison's Highways spending falling ~62%
at FY1972. Nationally, **both** operations and capital spike at FY1972 and
return the next year — the signature of a census year sitting between two
sample years:

| year | cycle | operations | capital |
|---:|---|---:|---:|
| 1971 | sample | 2,676,629 | 1,858,942 |
| **1972** | **census** | **6,599,268** | **12,255,228** |
| 1973 | sample | 3,093,053 | 1,889,531 |

There is no corpus-wide operations/capital reclassification at FY1972.
Madison's own 1971→1972 movement may still be real; it is not a code-level
break. This is the single most common way to manufacture a false finding in
this corpus.

### F-006 — the FY2012 "category retirements"

Five categories appear to lose every row at FY2012. They are not retired —
all five codes carry rows through FY2023 (`E12`: 1,475 governments in 2012,
1,328 in 2022). The wide era (≤FY2011) materialises an **explicit $0 for every
government × every code**; the modern era emits only what a government reports.
The categories did not disappear, their explicit zeros did.

Tracked as **#64**, which sparsifies the wide era and replaces this with one
`fin_code = "ALL"` representation-change entry at FY2012.

**If you hit this:** before cataloguing any break at FY2012, check whether the
code still carries rows *after* it.

### F-007 — the Public Welfare "gap" FY2012–FY2021

Madison reports no Public Welfare rows FY2012–FY2021, then reappears at FY2022
under a single new code. `SB171` already covers the FY2022 four-code-to-one-code
narrowing. The *gap* is the part this finding proposed cataloguing, as "missing
data, not zero spending."

Nationally there is no gap. Local governments (types 1/2/3) reporting direct
Public Welfare (`E74`/`E75`/`E77`/`E79`):

| year | local reporters | local total |
|---:|---:|---:|
| 2011 | 3,286 | $38.80B |
| 2013 | 3,098 | $37.16B |
| 2017 | 6,733 | $44.25B |
| 2021 | 2,645 | $49.32B |
| 2023 | 2,420 | $66.40B |

Reporting is continuous and the dollars grow throughout. (The 2012/2017/2022
peaks are the census years — compare census-to-census or sample-to-sample.)
Madison's decade of absence is a per-government reporting pattern, not a
code-level event.

**If you hit this:** in the modern era an absent row means *not reported*, not
`$0` — that is the `SB194` contract. A government-specific absence needs a
government-specific explanation; it is not evidence the code stopped being
collected.

### F-022 — M80 at FY2018

Wisconsin-specific: local reporting gaps at FY2018–FY2019, partially recovers
FY2020–21, then ends with the national FY2022 local-scope change. Recorded as
`KE022` in [`data/known_events.csv`](../data/known_events.csv) (type- and
state-scoped), not here. The separate **national** FY2022 M-family change — 27
of 28 local-scope M-codes to zero, all absorbed into `M89`, state scope
untouched — is measured on #61 and commissioned to Wave 5.

## Open Work

Items not yet implemented but tracked here for future agents:

1. ~~**`tests/testthat/test-series_breaks.R`** — Add a test that asserts the count of `joinable = "yes"` rows is stable.~~ Done (Wave 4.2b).
2. **Long-format flag** — Phase E should join `series_breaks.csv` to the long-format output and emit a `joinable` column per row, so downstream consumers can filter without re-loading the catalog. Alternatively, use `cog_code_info()` at query time.
3. **`unknown_item_codes_modern_{year}.csv` integration** — When a modern item code doesn't resolve in `data/item_code_xwalk.csv`, cross-check against `series_breaks.csv` to flag whether it's a known new-since-2005 code.
4. **Coverage validation** — Cross-reference each row's claimed `fin_code` against `data/wide_to_long_xwalk.csv` to confirm the legacy code exists in the source. Several rows currently have empty `fin_code` because the code is identified only by aggregate name (e.g. "FullFaith_*").
5. **Add 2012-data-side codes** — `series_breaks.csv` is currently keyed by legacy `fin_code`/`sas_var`. Add a `modern_item_code` column populated from `cog_explorer/data/item_code_xwalk.csv` so cross-format lookups work in either direction.
6. **Pre-2005 Corrections / Judicial disaggregation** — The legacy `-05` aggregate bundled Corrections *and* Judicial & Legal functions before the FY2005 redesign (see `SB109`, `SB110`, `SB111`, `SB112`, `SB113`). The split is not 50/50 and cannot be recovered from pipeline data alone. Phase M's aggregate fallback is deliberately scoped to `effective_years = 2005-2011`; pre-2005 Phase L cells for Corrections stay zero (and Judicial & Legal correspondingly underreports by the bundled amount). A future phase could propose a defensible split using an external anchor such as BLS Occupational Employment Statistics (OES) ratios of correctional officers vs judicial staff by state and year, applied to the legacy `-05` total.
    - **Code linkages to update together if the split is ever implemented:**
      - Legacy aggregate row: `item_code = "-05"`, `is_aggregate = TRUE`, in `long_{2000..2004}.parquet` (Phase E emits these once Phase M lands).
      - Modern leaf codes: `E04, E05, F04, F05, G04, G05` (Corrections) and `E25, F25, G25` (Judicial & Legal).
      - Crosswalks: `data/wide_to_long_xwalk.csv` (aggregate flag), `data/legacy_aggregate_map.csv` (Phase M mapping; add a `pre_2005_split` column or a second row with adjusted coverage).
      - Series breaks: extend `SB109`–`SB113` `join_advice` to reference the OES-anchored split methodology.
      - Phase L code: `R/summary_table.R::build_summary_cell()` fallback — add a per-year weighting factor lookup table.
      - Documentation: update `data/summary_alignment_notes.md` FY2005 section and `docs/pipeline.md` § Phase M.

## Sources

- [`docs/userguide/2005_revisions.md`](userguide/2005_revisions.md) — Verbatim Census documentation of the FY2005 redesign (the primary source for items SB001–SB084).
- [`docs/userguide/02_variables.md`](userguide/02_variables.md) — Per-variable coverage flags (cols J–S) for "2005 et seq." vs "2004 and earlier".
- [`docs/userguide/07_formulas.md`](userguide/07_formulas.md) — SAS derivation formulas; source for the 1976/1977 dollar precision caveat.
- [`docs/archive/reconciliation_task.md`](archive/reconciliation_task.md) — Display-name to sas_dbf reconciliation; companion document.
- `inst/extdata/IndFin_fixture/_IndFin_1967-2012/_ReadMe_First_IndFin.txt` — Census readme with the 2002–2006 imputation exclusion note.
- [`CLAUDE.md`](../../CLAUDE.md) — FIPS 66 (Guam) correction.
