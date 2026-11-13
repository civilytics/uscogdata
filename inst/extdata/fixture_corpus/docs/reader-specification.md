# Reader Specification v0.1 — uscogdata corpus contract

Language-neutral contract that any compliant reader for the uscogdata corpus
must implement. The R package `uscogdata` is the reference implementation;
future Python/Go/etc. ports implement the same contract.

## 1. Corpus layout

Published under a Nextcloud-hosted root (URL in `USCOGDATA_URL` env var), and
mirrored to the public Hugging Face dataset
[`civilytics/us-cog-finance`](https://huggingface.co/datasets/civilytics/us-cog-finance)
(`hf://` reads / bulk access; not in the live API's read path). Both surfaces
mirror the same publish tree. The **published year floor is FY1967** (the full
legacy series; `config.yml publish_min_year`). As-of-year county
(`fips_county_asof`) is NA for a small set of pre-2012-dissolved geographies
catalogued in `data/dissolved_geographies.csv` (Nansemond VA→Suffolk 1974, etc.);
present-geography `fips_state`/`fips_county` are always populated. The root
contains:

```
manifest.json
data/
  long/
    year=1967/part-0.parquet
    year=1970/part-0.parquet
    ...
    year=2023/part-0.parquet
  canonical_fips_xwalk.parquet
  canonical_alias.parquet
  summary_categories.parquet
docs/
  README.md
  data_dictionary.md
  series_breaks.md
  reader-specification.md
```

`manifest.json` is the authoritative index. Readers MUST validate it on
session open.

### 1.1. Year=2012 is modern-source only

The `year=2012/part-0.parquet` partition contains rows from the modern
Individual Unit Files (`Fin_GID_2012.txt` + `2012FinEstDAT_*_pu.txt`) only.
Legacy wide-format 2012 content is deliberately excluded from the published
corpus to preserve the invariant that no partition mixes the two source
families. Readers can therefore treat any year as a single-source partition
and never need to de-duplicate.

The pipeline retains the legacy 2012 long frame as an internal fixture for
cross-era validation (it is used by `validate_2012_dual_format` /
`compare_2012_boundary` to prove that the modern↔legacy crosswalks line up),
but it is not part of the published artifacts.

## 2. manifest.json schema (schema_version = 6)

```json
{
  "schema_version": 6,
  "built_at": "2026-07-22T...",
  "pipeline_commit": "<short-sha>",
  "data_vintage": {
    "source_vintages": { "...": "per-source vintage stamps from the registry" },
    "registry_rows": 0,
    "acs_vintage": "..."
  },
  "scope": {
    "gov_types_included": [0, 1, 2, 3],
    "gov_types_excluded": [4, 5],
    "scope_note": "v0.1: state, county, municipal, township only"
  },
  "schema": {
    "long_column_count": 28,
    "long_columns": ["fips_state", ...],
    "data_dictionary": "docs/data_dictionary.md"
  },
  "files": {
    "long_partitions": [
      {"year": 1967, "path": "data/long/year=1967/part-0.parquet",
       "sha256": "...", "row_count": 12345, "size_bytes": 98765}
    ],
    "metadata": [
      {"path": "data/canonical_fips_xwalk.parquet", "sha256": "...", "description": "..."},
      {"path": "data/canonical_alias.parquet", "sha256": "...", "description": "..."},
      {"path": "data/summary_categories.parquet", "sha256": "...", "description": "..."}
    ]
  },
  "series_breaks_ref": "docs/series_breaks.md",
  "reader_spec_ref": "docs/reader-specification.md"
}
```

## 3. Long parquet schema (28 columns)

See `docs/data_dictionary.md` § "Long parquet columns (28-column schema v6)"
for full per-column documentation. Column order is authoritative; readers
SHOULD NOT rely on positional indexing but MUST accept all 28 columns.

> **Schema v6 (2026-07-21) — BREAKING changes vs v5/v4.** Two kinds:
> 1. **Rename (fails loudly):** `fips_state_code` → `fips_state_asof`,
>    `fips_county_code` → `fips_county_asof` (same as-of-year meaning, clearer
>    name). A consumer selecting the old names errors on a missing column.
> 2. **Same name, CHANGED MEANING (silent):** `fips_state` / `fips_county` are
>    now the **present/harmonized** geography (each government's *current*
>    county identity carried back to every year, derived from `canonical_govid`),
>    NOT the as-of-year value they held under v4/v5. A join or filter on these
>    won't error — it returns present-geography values on historical rows. Use
>    `fips_state_asof` / `fips_county_asof` for as-of-year geography, and
>    `cog_legacy_state` / `cog_legacy_county` for the raw GOVS source codes.
>
> v4→v5 added `harmonized_code` and `survey_weight` (24→26); v5→v6 renamed the
> two `_code` columns and inserted `cog_legacy_state`/`cog_legacy_county`
> (26→28).

| # | Column | Type | Notes |
|---|--------|------|-------|
| 1 | fips_state | integer | **Present/harmonized** 2-digit FIPS state (from `canonical_govid` 1–2), carried back to every year |
| 2 | type | integer | 0=State 1=County 2=Muni 3=Township 4=SplDist 5=ISD |
| 3 | fips_county | integer | **Present/harmonized** FIPS county (from `canonical_govid` 4–6); 0/NA for states. Auto-handles renames/splits |
| 4 | govid | character | Census internal unit ID |
| 5 | gov_blank | character | Reserved Census field |
| 6 | gov_name | character | Government name |
| 7 | county_name | character | County name |
| 8 | fips_state_asof | integer | As-of-year FIPS state (renamed from `fips_state_code`) |
| 9 | fips_county_asof | integer | As-of-year FIPS county (renamed from `fips_county_code`); legacy from the GOVS→FIPS crosswalk, modern from source |
| 10 | cog_legacy_state | integer | Raw GOVS state code. Populated FY1967/1970–2016; `NA` FY2017+ |
| 11 | cog_legacy_county | integer | Raw GOVS county code. Populated FY1967/1970–2016; `NA` FY2017+ |
| 12 | fips_place_code | character | Place FIPS code |
| 13 | population | numeric | Population |
| 14 | popyear | integer | Year of population estimate |
| 15 | enrollment | numeric | School enrollment |
| 16 | enrollyear | integer | Year of enrollment estimate |
| 17 | function_code | character | Census function code |
| 18 | sch_level_code | character | School level code |
| 19 | fiscal_year_end | character | Fiscal year end date |
| 20 | srvy_year | integer | Survey year |
| 21 | item_code | character | Finance item code (e.g. T01, E62) |
| 22 | amt | numeric | Amount in $1,000s |
| 23 | srv_data | character | Survey data flag |
| 24 | impute_flag | character | Imputation flag |
| 25 | is_aggregate | logical | TRUE if row is a subtotal aggregate |
| 26 | canonical_govid | character | Stable 12-char canonical ID (PID census_id frozen at FY2023 vintage; `9xxxxx`-unit corpus-assigned ids for governments never observed 2017+). See `docs/data_dictionary.md` § col 26 / `docs/ids_reference.md` § "Canonical namespace (Phase P)". |
| 27 | harmonized_code | character | Cross-vintage comparable item code; `NA` on aggregate rows |
| 28 | survey_weight | numeric | Legacy IndFin `Weight` (informational only — never aggregate with it); `NA` for modern-source rows |

### 3.1 Spending concepts: Direct, Total, and the M-code

For each spending function the corpus publishes **one flavor: Direct** — a
government's own spending (its `E`/`F`/`G` leaves), carried in the legacy era as
the per-function family aggregate (`-NN`, e.g. `-05`) and in the modern era as
the leaves themselves. Census's **Total** concept is `Direct + M-code + L-code`
(the function's intergovernmental payments to **local** governments, e.g.
`M05`, plus to **state** governments, e.g. `L05`). The identity **`Total =
Direct + M + L`** holds arithmetically, and both code families are published
in both eras — but "published" does not mean "sitting on a leaf row a reader
can sum directly." In the **legacy era (≤ FY2011)** several IG code families —
`M05`, `M12`, `M47`, `M89`, `L47`, `L89` — are published **only** as
`is_aggregate = TRUE` rows, because the wide source files expose those
families only as aggregates; their leaves first appear in the modern era.
Measured on the published corpus: in FY2007 only **26.3%** of
intergovernmental dollars sit on non-aggregate rows (129,835,142 of
493,510,366). `M12` alone is 291,293,845 that year — 59% of the year's IG
total — and is `is_aggregate = TRUE`, as are `M89`, `M47`, and `L--`. A reader
that honors the `NOT is_aggregate` rule in §4 and then tries to reconstruct
Total by summing M/L leaves out of `spending_long` therefore sees only a
minority of legacy IG dollars and computes a "Total" that is silently ≈
Direct. Total must instead be assembled **year-scoped**, the way
`ige_local_m47_wide`, `ige_local_m89_wide`, `ige_state_l47_wide`,
`ige_state_l89_wide`, and `corrections_ig_local_combined` already do (see
`data_dictionary.md` for the recipe-level detail) — it cannot inherit the
basis views' leaf-only filter.
`L` is identically 0 for state governments, so for a state `Total = Direct +
M` — but `L` is material for local governments (91.6% of `M` for counties,
188.3% for cities) and must not be dropped.

**A compliant reader MUST resolve "total spending" to the right concept per query
shape** — the dividing line is whether the query sums across *governments*:

| Query shape | Concept | Rule |
|---|---|---|
| One government (or its own trend) | Direct **or** Total, consistently | either is valid; do not mix concepts across years |
| Any aggregation across governments | **Direct only** | summing Total double-counts intergovernmental flows (a grant is in the payer's Total and again in the recipient's Direct) |

Worked identity (Alabama state government, corrections, FY2007, $1,000s):
`-05` (Direct) `= E05+F05+G05 = 487,175`; `+ M05 (27,210) + L05 (0) =
514,385` (Total). Alabama is a state, so `L05` is 0; for a city or county the
`L` term is material and must be included.
Full explanation, the modern-era leaf caveat, and query examples:
[`data_dictionary.md`](data_dictionary.md) § "Total spending".

## 4. Required DuckDB views

A compliant reader registers these views on session open (pseudocode using the
Nextcloud public share URL pattern):

### `long` — raw unfiltered data

```sql
CREATE OR REPLACE VIEW long AS
SELECT * FROM read_parquet(
  '{USCOGDATA_URL}/data/long/**/*.parquet',
  hive_partitioning = true
);
```

### `spending_long` — spending codes only

```sql
CREATE OR REPLACE VIEW spending_long AS
SELECT * FROM long
WHERE LEFT(item_code, 1) IN ('E', 'F', 'G', 'K')
  AND NOT is_aggregate;
```

### `revenue_long` — revenue codes only

```sql
CREATE OR REPLACE VIEW revenue_long AS
SELECT * FROM long
WHERE LEFT(item_code, 1) IN ('T', 'A', 'B', 'C', 'D', 'U')
  AND NOT is_aggregate;
```

Readers MUST exclude `is_aggregate = TRUE` rows from all sum operations.

This rule is exactly right for **Direct** — `spending_long`/`revenue_long` are
Direct-only views by construction. It does NOT mean a legacy-era **Total** can
be reconstructed by summing M/L leaves out of these views: per §3.1, several
IG code families are aggregate-only before FY2012, so a naive leaf-only sum
silently collapses toward Direct instead of Total. A reader offering Total
must assemble it year-scoped, per §3.1, not by relaxing this filter.

## 5. Verb contracts (uscogdata MVP)

> **⚠️ This section is the ORIGINAL design contract and has diverged from the
> shipped `uscogdata` package.** The verbs below (`cog_govs`, `cog_long`,
> `cog_summary`) were never exported. The package's actual public API (see
> `uscogdata`'s `NAMESPACE`) is: `cog_open`/`cog_mirror`, `cog_spending`,
> `cog_revenue`, `cog_categories`, `cog_recipes`, `cog_gov_search`,
> `cog_find_peers`, `cog_peer_compare`, `cog_geographic_rollup`,
> `cog_basket_resolution`, `cog_basket_unresolved`, `cog_explain`,
> `cog_manifest`. Treat the contracts below as design intent; consult the
> package's own function docs for the current signatures. A full rewrite of
> this section to the shipped API is tracked with the user-surface work in
> issue #42 / uscogdata#6.

### cog_open

Opens a DuckDB connection to the corpus.

**Inputs:**
- `url` (character, default `Sys.getenv("USCOGDATA_URL")`) — Nextcloud share root

**Side effects:**
- Downloads/caches `manifest.json`
- Validates `schema_version == 6`
- Validates `scope.gov_types_included` covers expected types
- Registers **15** DuckDB views from the shipped `.sql` files (`long`;
  `spending_long`/`revenue_long` and their `_harmonized` variants; the
  `canonical_fips_xwalk`, `summary_categories`, `gov_population_yearly`,
  `harmonization_map`, `harmonization_recipes`, `series_breaks_pq` reference
  views; and the `*_annotated` / `*_annotated_harmonized` views). The
  harmonization/annotated-harmonized views are skipped when
  `schema_version < 5`.
- Sets session-global connection

**Output:** Connection object (invisibly)

### cog_govs

Returns the canonical government registry.

**Inputs:**
- `con` — connection from `cog_open`
- `types` (integer vector, default `0:3`) — gov_types to include
- `name_pattern` (character, default NULL) — regex filter on `gov_name`

**Output columns:** `canonical_govid`, `gov_name`, `type`, `fips_state`,
`fips_county`, `fips_place_code`, `acs_pop`

### cog_long

Returns raw long data (thin wrapper over the `long` view).

**Inputs:**
- `con` — connection
- `govids` (character vector, default NULL = all in scope)
- `years` (integer vector, default all available)
- `item_codes` (character vector, default NULL = all)
- `include_aggregates` (logical, default FALSE)

**Output:** tibble with 28 columns matching the long parquet schema.

### cog_spending

Returns summarized spending by category.

**Inputs:**
- `con` — connection
- `govids` (character vector)
- `years` (integer vector)
- `category` (character vector, default NULL = all)
- `spend_subtype` (character `"operations"` | `"capital"` | NULL)
- `per_capita` (logical, default FALSE)
- `adjust_to_year` (integer, default NULL)

**Output columns:** `year`, `canonical_govid`, `gov_name`, `spend_subtype`,
`category`, `amt_nominal`, [`amt_real`], [`amt_per_capita_nominal`],
[`amt_per_capita_real`], `codes_included`, `aggregate_fallback`, `notes`

One row per `(year × canonical_govid × spend_subtype × category)`.
Real/per-capita columns only present when corresponding flag is set.

### cog_revenue

Mirror of `cog_spending` for revenue categories.

**Inputs/output:** Same structure; `revenue_subtype` ∈ `{own_source, federal,
state, local_aid}` replaces `spend_subtype`.

### cog_summary

Cross-year totals, one row per `(canonical_govid × category)`.

**Inputs:**
- `con` — connection
- `govids` (character vector)
- `years` (integer vector)
- `categories` (character vector, default all)
- `per_capita` (logical, default FALSE)

**Output columns:** `canonical_govid`, `gov_name`, `category`, and one
`{year}` column per requested year.

### cog_mirror

Downloads the full corpus to a local directory for offline use.

**Inputs:**
- `con` — connection
- `dest_dir` (character)
- `overwrite` (logical, default FALSE)

**Side effect:** Writes Hive-partitioned parquet tree to `dest_dir`.

### cog_explain

Returns a named list with human-readable provenance for the most recent verb
call.

**Output fields:** `verb`, `target`, `years`, `category`, `codes_summed`,
`aggregate_fallback`, `series_break_refs`, `manifest_sha`, `sql_query`.

## 6. Provenance contract

Every verb result carries a `provenance` attribute (R list / JSON dict). All
fields are required:

| Field | Type | Description |
|-------|------|-------------|
| `verb` | string | name of the verb |
| `call` | string | deparsed call expression |
| `target` | string[] | canonical_govids queried |
| `years` | int[] | years queried |
| `category` | string[] or null | categories queried |
| `scope` | object | manifest scope block |
| `codes_summed` | string[] | item_codes included in sum |
| `aggregate_fallback` | bool | true if any aggregate row was used |
| `transformations` | string[] | e.g. ["real_2022", "per_capita"] |
| `series_break_refs` | string[] | SB codes touching this query |
| `manifest` | object | manifest built_at + pipeline_commit |
| `sql_query` | string | DuckDB SQL executed |

## 7. Scope handling

Readers MUST:
1. Read `manifest.scope.gov_types_included` on `cog_open`.
2. Error with a clear message if the corpus scope does not cover the
   government types the caller requested.
3. Never silently omit types that the caller expected to be present.

## 8. Series break awareness

Readers SHOULD surface warnings when a query spans a known series break. The
canonical break list is in `docs/series_breaks.md` (also in the corpus docs/
directory). At minimum, warn on:

- Queries spanning FY2005 for categories with `joinability != "yes"`.
- Queries spanning FY2017 (GID→PID transition) without canonical_govid
  reconciliation.

## 9. Versioning

| manifest.schema_version | Reader Spec version | Notes |
|-------------------------|---------------------|-------|
| 2 | v0.1-draft | Never shipped: year=2012 partition mixed legacy + modern sources, producing duplicate `(canonical_govid, item_code)` rows. Do not consume. |
| 3 | v0.1        | First shipped version. year=2012 is modern-source only; PID-era canonical_govid FIPS-bridged via `canonical_fips_xwalk`. |
| 4 | v0.1        | Phase P canonical namespace: `canonical_govid` is now a uniform 12-char id (PID census_id frozen at FY2023 vintage, or a corpus-assigned `9xxxxx`-unit id) for every government across its full observed life, replacing the mixed 9-char/12-char scheme. New metadata file `canonical_alias.parquet` (the resolver's only lookup table) ships alongside `canonical_fips_xwalk.parquet`. See `docs/ids_reference.md` § "Canonical namespace (Phase P)". |
| 5 | v0.1        | Phase R2 harmonization: long schema grows 24→26 columns, adding `harmonized_code` (cross-vintage concept id) and `survey_weight`. New reference views `*_harmonized`, `harmonization_map`, `harmonization_recipes`, `series_breaks_pq` register when `schema_version >= 5`. |
| 6 | v0.1        | Current. Long schema 26→28 columns. **Breaking:** `fips_state_code`→`fips_state_asof`, `fips_county_code`→`fips_county_asof` (rename, fails loudly); and `fips_state`/`fips_county` change MEANING to present/harmonized geography (silent — see the schema-v6 banner in §3). Build window extended to FY1967/1970; **published floor lowered to FY1967** (dissolved-geography as-of-county NA-filled via `data/dissolved_geographies.csv`). |

Breaking changes to the schema (column addition, type change, removed column)
or to the partition semantics (source mixing, row count by unit-of-analysis)
increment `schema_version`. Non-breaking changes (new parquet partition, doc
update) do not.
