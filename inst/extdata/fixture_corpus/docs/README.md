# cog_pipeline documentation index

This folder is the single home for `cog_pipeline` reference material.
Start here when you arrive; everything else is one hop away.

## Reading order for a new contributor

1. [`../README.md`](../README.md) — 1-page project intro + quick start.
2. [`STATUS.md`](STATUS.md) — **live** progress log. Which phases are
   implemented, what the last run produced, what's pending.
3. [`pipeline.md`](pipeline.md) — long-form design record for Phases A–N.
   **Frozen historical reference** (predates schema v6 / Phase P / the gate
   battery); read it for original design rationale, and trust the code +
   `STATUS.md` for current behaviour.
4. [`data_dictionary.md`](data_dictionary.md) — source-file vocabulary,
   crosswalk inventory, and the dollar-unit / government-type
   conventions every function assumes.
5. [`ids_reference.md`](ids_reference.md) — authoritative reference for
   every ID width and namespace (GOVS 9-char, GOVS 14-char, FIPS
   12-char, LILP 12-char). Read before touching `R/ids.R` or
   `R/read_modern.R`.
6. [`series_breaks.md`](series_breaks.md) — catalog of every known
   classification change in the 1967–present series, with explicit
   joinability verdicts. Read before designing any cross-boundary
   analysis.

## Topic map

| If you want to… | Read |
|---|---|
| Understand the overall architecture | [`pipeline.md`](pipeline.md) § 2 |
| Add or modify a phase | [`pipeline.md`](pipeline.md) § Phase X, then [`STATUS.md`](STATUS.md) |
| Interpret a column in the long parquet | [`data_dictionary.md`](data_dictionary.md) + [`userguide/02_variables.md`](userguide/02_variables.md) |
| Know what "total spending" means (Direct vs Total, and cross-government sums) | [`data_dictionary.md`](data_dictionary.md) § "Total spending" + [`reader-specification.md`](reader-specification.md) § 3.1 |
| Translate between legacy and modern IDs | [`ids_reference.md`](ids_reference.md) |
| Know whether two years are joinable for a given item code | [`series_breaks.md`](series_breaks.md) + `data/series_breaks.csv` |
| Follow the FY2005 classification changes | [`series_breaks.md`](series_breaks.md) § 2005 + [`userguide/2005_revisions.md`](userguide/2005_revisions.md) |
| Find the SAS derivation formula for a computed variable | [`userguide/07_formulas.md`](userguide/07_formulas.md) + `data/wide_derived_formulas.csv` |

## What lives where

### Active / canonical (read these)

| File | Role | Status |
|---|---|---|
| [`STATUS.md`](STATUS.md) | Live progress log, per-phase state | **Living** — update after every session |
| [`pipeline.md`](pipeline.md) | Long-form design record, Phases A–N | **Frozen** — historical (pre-v6); trust code + STATUS.md for current behaviour |
| [`data_dictionary.md`](data_dictionary.md) | Source-file inventory, crosswalk list, unit conventions | **Living** |
| [`ids_reference.md`](ids_reference.md) | ID systems + file layouts (FinEstDAT, GID, PID, IDxWalk) | **Living** |
| [`series_breaks.md`](series_breaks.md) | Catalog of 188 documented series breaks | **Living** (paired with `data/series_breaks.csv`) |
| [`gate_inventory.md`](gate_inventory.md) | Every publish-blocking validation gate: target, config block, failure meaning, exemption catalogs | **Living** |
| [`source_versioning.md`](source_versioning.md) | Source registry, vintage pinning, release records — the source-integrity machinery | **Living** |
| [`reader-specification.md`](reader-specification.md) | Language-neutral corpus contract (layout, manifest, DuckDB views, provenance). Ships in the corpus | **Living** |
| [`census_bridge.md`](census_bridge.md) | GOVS↔FIPS bridging reference | **Living** |
| [`2012_boundary_validation.md`](2012_boundary_validation.md) | The 2012 dual-source golden-gate playbook (model for `gate_inventory.md`) | **Living** |
| [`year_extension_runbook.md`](year_extension_runbook.md) | Runbook for extending the corpus to a new fiscal year | **Living** |

### UserGuide excerpts (reference material — treat as read-only)

[`userguide/`](userguide/) holds prose transcriptions of the Census-published
`UserGuide.xls` sheets that the pipeline depends on. They are consulted but
never edited.

| File | Sheet | When to consult |
|---|---|---|
| [`userguide/01_years.md`](userguide/01_years.md) | 1. Years | Year-coverage lookups |
| [`userguide/02_variables.md`](userguide/02_variables.md) | 2. Variables | Authoritative variable catalog (`sas_dbf`, `fin_code`, coverage eras) |
| [`userguide/04_reference.md`](userguide/04_reference.md) | 4. Reference | `ALLids` and `IDxWalk` documentation |
| [`userguide/05_user_notes.md`](userguide/05_user_notes.md) | 5. User Notes | Census caveats incl. the pre-1977 whole-dollar rounding (SB085) the ≤1976 gate tolerance traces to |
| [`userguide/07_formulas.md`](userguide/07_formulas.md) | 7. Formulas | Derivation formulas (canonical machine-readable copy is `data/wide_derived_formulas.csv`) |
| [`userguide/2005_revisions.md`](userguide/2005_revisions.md) | 2005 Revisions | Coverage/classification changes at the FY2005 break |
| [`userguide/changes.md`](userguide/changes.md) | Changes Log | Errata / revisions to the UserGuide itself |

### Historical / completed (kept for provenance)

These documents describe *completed* refactors. Their content is now
either in the code or reflected in the living docs above. They are
retained so that future maintainers can reconstruct *why* current
structure exists. The `history_` prefix signals "decision record for a
landed refactor"; the `archive/` subfolder holds one-shot reports and
fully-superseded design notes whose conclusions are now baked into the
code.

| File | Describes | Status |
|---|---|---|
| [`history_phase_c_h.md`](history_phase_c_h.md) | 2026-04-09 rebuild of Phase C around official GOVS crosswalks; absorption of Phase H | **Complete** — historical record |
| [`history_phase_wide_long.md`](history_phase_wide_long.md) | 2026-04-13 Wave 4 boundary reconciliation at 2012; 6-status gate T5 classification | **Complete** — historical record |
| [`archive/reconciliation_task.md`](archive/reconciliation_task.md) | Derivation of `data/display_to_sas_dbf.csv` by positional UserGuide alignment | **Resolved** — canonical solution now in the crosswalk CSV itself |
| [`archive/id_mechanical_suffix_test.md`](archive/id_mechanical_suffix_test.md) | 2026-04-09 one-shot report confirming the `paste0(legacy9, '00000')` rule for types 2/3/4/5 | **Superseded** — result is baked into Phase C; kept only for audit provenance |
| [`archive/plan_phase_jkl.md`](archive/plan_phase_jkl.md) | Original plan for Phases J / K / L | **Complete** — all three landed April 2026 |
| [`archive/plan_phase_m.md`](archive/plan_phase_m.md) | Original plan for Phase M (aggregate subtypes) | **Complete** — landed 2026-04-21 |
| [`archive/plan_phase_n.md`](archive/plan_phase_n.md) | Original plan for Phase N (corpus publication) | **Complete** — landed 2026-04-22 |
| [`archive/plan_phase_n_tasks.md`](archive/plan_phase_n_tasks.md) | Phase N task breakdown (uscogdata reader) | **Complete** |

### Measurement & checkpoint records (point-in-time evidence)

Dated evidence artifacts from the Phase Q / R measurement and checkpoint
process. Retained for provenance; **not** live docs — each captures the state at
its own date. Volatile counts inside them are snapshots, not current values.

| File | Records |
|---|---|
| [`deep_review_2026-07-23.md`](deep_review_2026-07-23.md) | The 2026-07-23 five-pass deep review (correctness / docs / simplification); parent issue #27, findings #28–#42 |
| [`phase_q_baseline.md`](phase_q_baseline.md) | Phase Q full-corpus 2012 golden-gate baseline (G1–G5) |
| [`phase_q_checkpoint.md`](phase_q_checkpoint.md) | Phase Q checkpoint ruling record |
| [`phase_q_residue.md`](phase_q_residue.md) | Phase Q residual-item dispositions |
| [`phase_r2_measurement.md`](phase_r2_measurement.md) | Phase R2 harmonization coverage/conservation measurements |
| [`phase_r3_measurement.md`](phase_r3_measurement.md) | Phase R3 spike/cliff/catalog measurements |
| [`phase_r_anchor_report.md`](phase_r_anchor_report.md) | Phase R external-anchor spot-checks |
| [`phase_r_harmonization_review.md`](phase_r_harmonization_review.md) | Phase R harmonization-map review |

## Open consolidation opportunities (lower priority)

- The Phase G layout tables in `ids_reference.md` and the Phase G
  section of `pipeline.md` restate each other. Pick one as canonical
  (suggest `ids_reference.md` since it is the ID-system reference) and
  have the other link out rather than duplicate the row/byte
  arithmetic.
- `STATUS.md` currently holds both a live state table *and* detailed
  per-phase implementation notes that partially duplicate
  `pipeline.md`. **`pipeline.md` is now a frozen historical design record
  (through Phase N); where it and `STATUS.md` disagree, trust `STATUS.md`
  and the code** — `pipeline.md` predates schema v6, Phase P, and the gate
  battery. Consider trimming `STATUS.md` to: state table, last-run summary,
  next-session prompt.

## Where to add *new* docs

- **Short-lived design notes** (one refactor, one feature) → write into
  an open branch, then either merge the relevant content into
  `pipeline.md` / `STATUS.md` and delete, or move to `docs/archive/`
  once the work lands. Don't leave orphan `refactor_*.md` in `docs/`.
- **Living reference** (a new source file, a new phase, a new external
  dataset) → extend the appropriate existing canonical doc above
  rather than creating a new top-level file.
- **Generated reports** (gate results, coverage stats) → write to
  `data/` as CSV/Parquet and point at them from `STATUS.md`; avoid
  committing PDF or Markdown snapshots that go stale the moment the
  pipeline re-runs.
