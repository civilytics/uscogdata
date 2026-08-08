# `uscogdata` 0.1.0 — public release

**Date:** 2026-08-08 · **Status:** design, awaiting approval
**Scope:** release-readiness, README, NEWS. Distribution mechanics recorded here as
decided, sequenced after the package is clean.

`uscogdata` is feature-complete and the corpus it reads has been public on
HuggingFace since 2026-08-07 (294 downloads as of this writing). The API built on
it is live. What does not exist is a public *package*: the repo is private, there
is no install path, and — measured, not assumed — **a stranger who installed it
today could not read the corpus at all.**

This spec covers making that untrue.

## Decisions locked

| Decision | Choice |
|---|---|
| Canonical source | `gitea.civilytics.org/Civilytics/uscogdata`, flipped public |
| Public mirror | `github.com/civilytics/uscogdata` — issues, PRs, multi-OS check, CDN |
| Mirror mechanism | Gitea Actions non-force `git push` (not a push mirror) |
| Binaries | `civilytics.r-universe.dev`, registry pinned to a release tag |
| Author of record | Jared E. Knowles `<jared@civilytics.com>`, ORCID `0000-0003-0005-9478` |
| Copyright | Civilytics Consulting LLC (`cph`, `fnd`) |
| License | MIT (package) · CC-BY-4.0 (corpus) |
| Corrections intake | Deferred — see *Out of scope* |
| Other packages | Parked until this one walks the path end to end |

## P0 — the corpus is unreachable

Two independent faults, either of which alone is fatal.

**No corpus URL exists.** `R/config.R` defaults to the literal
`REPLACE_WITH_SHARE_TOKEN` sentinel, and no file in the repo supplies a working
one. A new user calling any verb gets `uscogdata_url_not_configured` with no path
to resolution.

**Remote reads are broken regardless.** Every partitioned view globs:

```sql
FROM read_parquet('{url}data/long/**/*.parquet', hive_partitioning = true)
```

DuckDB 1.5.5 refuses globs over generic HTTP. Its suggested
`allow_asterisks_in_http_paths` escape hatch does not help — it forwards the
literal `**/*` as a filename and 404s, because plain HTTP exposes no directory
listing to expand against.

The package therefore works only against a **local path**. That is how the API
runs it (`CORPUS_HOST_PATH` is a host mount on maxwell) and how the tests run
(bundled fixture), which is why the fault went unnoticed. The README's headline
claim — *"Reads the published corpus directly from Nextcloud via DuckDB httpfs —
no local bulk downloads required"* — is currently false.

### Fix: enumerate from the manifest, do not glob

`manifest.json` already lists every partition under `files.long_partitions[]`
with `path`, `year`, `sha256`, `row_count` and `size_bytes` — 56 of them.
Substituting an explicit file list for the glob was measured against the
published corpus on 2026-08-08:

| Path | Result |
|---|---|
| `https://…/data/long/**/*.parquet` (default) | error — globs unsupported over HTTP |
| same, `allow_asterisks_in_http_paths = true` | error — literal `**/*` 404s |
| `hf://datasets/civilytics/us-cog-finance/…` glob | 46,148,034 rows |
| **explicit list over plain https** | **46,148,034 rows** |

`hive_partitioning = true` still recovers `year` from the paths under
enumeration, so no downstream view or verb changes.

Enumeration is preferred over `hf://` deliberately. It is **host-agnostic** —
Nextcloud, HuggingFace, or any static server take the same code path — where
`hf://` would tie the default to one vendor's protocol and still need
special-casing, since manifest fetching goes through `httr2`, which cannot speak
`hf://`. Enumeration also *removes* a dependency (globbing) rather than adding
one, and the manifest's per-file `sha256` becomes available for integrity
checking later.

Views are registered from `inst/sql/` with `{url}` substitution in
`R/views.R:.register_views()`. The list must be built once per session from the
already-fetched manifest and substituted the same way, so the change is confined
to view registration and does not touch verb code.

### Fix: ship a working default

`R/config.R`'s default becomes the public HuggingFace `resolve/main/` URL:
CC-BY-4.0, no token to publish, CDN-backed, and it keeps maxwell's uplink out of
the path — the same reasoning behind the GitHub mirror and r-universe.

This means `library(uscogdata)` followed by a verb works with **zero
configuration**, which is what makes the package demonstrable in a README and
later in a post. `USCOGDATA_URL` and `options(uscogdata.url=)` continue to
override, so the Nextcloud copy and local mirrors are unaffected.

The `uscogdata_url_not_configured` error class stays — it still fires for an
explicitly-set empty or placeholder URL — but ceases to be the default
experience.

### Consequence: `cog_mirror()` is promoted

Measured cost of the remote default, from efron on a good connection:

| | |
|---|---|
| Whole corpus | **190.6 MB**, 56 partitions, 46,148,034 rows, FY1967–FY2024 |
| One government, one year | 1.5 s |
| One government, all 56 years | 2.8 s |
| Disk written | **0.00 MB** — range requests only; `external_file_cache` is in-memory |

Nothing persists locally beyond the shared `httpfs` extension in `~/.duckdb` (a
few MB, once per machine, across all DuckDB use). Costs are RAM and per-query
bandwidth, since nothing caches between sessions.

Those timings are raw scans. Real verbs additionally join crosswalks, resolve
categories and assemble provenance, so end-to-end verb latency will be higher and
**must be re-measured once the fix lands** — it cannot be measured today.

The corpus being only 190.6 MB makes `cog_mirror()` a first-class option rather
than a developer footnote. The README presents **both paths**:

- **Remote (default, zero setup)** — trying it out, teaching, one-off questions.
- **Mirrored (`cog_mirror()`, 190 MB once)** — repeated or heavy analysis,
  offline work, reproducibility, or preferring not to depend on HuggingFace.

The second is also the honest answer to the vendor-dependency question raised by
defaulting to HuggingFace: **the escape hatch is one function call and 190 MB**,
after which no analysis touches an external service. The README says so
explicitly. That is the difference between a convenience default and lock-in.

## Release-readiness fixes

| # | Issue | Fix |
|---|---|---|
| 1 | `MaxCorpusSchema: 5` in DESCRIPTION; `.validate_schema()` accepts `4,5,6,7`; published corpus is **7** | `MaxCorpusSchema: 7` |
| 2 | `^vignettes$` in `.Rbuildignore` — both vignettes absent from the installed package, while README tells users to run `vignette("total-spending")` | Remove `^vignettes$`, `^doc$`, `^Meta$`. Both vignettes build offline (`total-spending` reads the bundled fixture; `population-denominators` is `eval = FALSE`) |
| 3 | `_pkgdown.yml` reference index covers 6 of 14 exports — pkgdown errors on missing topics | Add `cog_categories`, `cog_explain`, `cog_find_peers`, `cog_geographic_rollup`, `cog_manifest`, `cog_mirror`, `cog_peer_compare`, `cog_recipes`; set `url:` |
| 4 | No `URL:` / `BugReports:` in DESCRIPTION | Add both, pointing at the GitHub mirror |
| 5 | No `LICENSE.md`; `LICENSE` holder reads `Civilytics` | `usethis::use_mit_license("Civilytics Consulting LLC")` |
| 6 | README instructs stripping the fixture at release | Delete that section — see below |
| 7 | `Authors@R` is an org with no human | Jared E. Knowles `aut`/`cre` + ORCID; Civilytics Consulting LLC `cph`/`fnd` |

**On #6.** The advice to add `^inst/extdata/fixture_corpus$` to `.Rbuildignore`
is CRAN-sized thinking (5 MB limit) and this package is not going to CRAN.
Stripping the 15 MB fixture would break `total-spending.Rmd`, which reads from
it, and would leave r-universe and GitHub Actions unable to run the 28 test files
without a corpus credential. **The fixture is what lets `R CMD check` pass
anywhere with zero secrets** — precisely what public CI needs. It ships.

## README

The current README addresses someone standing inside the repo tree: status reads
"Under active development (Phase 2 of the cog_pipeline project)", it points at
`../cog_pipeline/docs/reader-specification.md`, the install line is commented
out, and developer, testing and release sections sit above anything a user needs.

Restructured around a stranger, in this order:

1. **What this is** — one paragraph, and what the corpus covers (types 0–3,
   FY1967–FY2024, 46M rows, 190.6 MB).
2. **Install** — r-universe first (binaries), git second.
3. **Quickstart that actually runs** — resolve a government, get its history,
   print provenance. No configuration step.
4. **Two ways to read the corpus** — remote default vs `cog_mirror()`, with the
   measured numbers and the independence note.
5. **Amounts are in full US dollars** — kept near the top. This is the errata
   most likely to produce a wrong answer that looks plausible.
6. **Concepts** — primary/direct/total spending, general/total revenue,
   coverage. Condensed, linking to the vignettes for the full treatment.
7. **How to cite** — `citation("uscogdata")`, corpus CC-BY-4.0 attribution.
8. **Contributing** — canonical-on-Gitea PR flow.

Developer notes, testing instructions and release procedure move to
`CONTRIBUTING.md`. Every path reference to a sibling repo is removed or replaced
with a URL that resolves for someone who has only this repo.

## NEWS.md

The current NEWS is a pre-release churn log: changes described relative to states
no user has seen ("Breaking: corpus schema_version 4", "the package now
requires…"), newest-first across the package's entire pre-release development
(2026-04-23 to 2026-08-04, 140 commits). To a newcomer evaluating whether to
depend on the package, it reads as instability.

**0.1.0 is rewritten as an initial release**: what the package does, what the
corpus covers, and the caveats that are genuinely load-bearing. The pre-release
history is not preserved in NEWS — it is in git, where it belongs.

The substantive content is migrated, not deleted. These are hard-won and belong
in documentation rather than buried in a changelog:

| Content | Destination |
|---|---|
| Coverage disclosure on multi-government aggregates (census vs sample years) | README concepts + `cog_geographic_rollup()` docs |
| `complete = TRUE` three-way absence semantics (`reported` / `census_zero` / `not_reported`) | `cog_spending()` / `cog_revenue()` docs |
| Series-break and corpus-break surfacing | README + `cog_explain()` docs |
| $1,000s → full dollars conversion | README, already prominent |
| Per-year F-33 population denominators | `population-denominators` vignette, already there |

This also makes NEWS reusable as raw material for the release announcement,
which is the stated downstream purpose.

## Distribution mechanics

Recorded as decided; executed after the package is clean and checks are green.

**Sequence matters.** r-universe publishes check results the moment a package is
registered. Registering before the fixes above land means a red badge on day one,
which is a worse first impression than a week's delay.

1. `gitleaks` over full history. A coarse grep found nothing across 140 commits
   and the default corpus URL is still the placeholder sentinel, but a proper
   scan is the gate on an irreversible action.
2. Flip the Gitea repo public. Disable Gitea issues on it, so there is exactly
   one inbox.
3. Create `github.com/civilytics/uscogdata`. Add `.github/workflows/` for the
   Windows/macOS/Linux `R CMD check` matrix — the platforms the Gitea runner
   cannot provide, and which this package has never been tested on despite
   depending on duckdb and httr2. Gitea reads `.gitea/workflows`, GitHub reads
   `.github/workflows`; both live in one tree without colliding.
4. Gitea Actions workflow pushing to GitHub **without `--force`**, so divergence
   fails loudly in CI rather than silently overwriting.
5. Add `jared@civilytics.com` as a verified secondary email on the GitHub
   account — r-universe links maintainer identity by matching DESCRIPTION's email
   against registered GitHub emails, and the association only takes effect on the
   next build.
6. Tag `v0.1.0`. Create `github.com/civilytics/civilytics.r-universe.dev` with a
   `packages.json` pinned to the tag, pointing at the GitHub mirror rather than
   Gitea so clone traffic stays off maxwell. Install the r-universe app.

### PR flow

Never press Merge on GitHub. A merge there is overwritten by the next sync, the
PR still displays "Merged", and nothing says otherwise.

```sh
git remote add github https://github.com/civilytics/uscogdata.git
git config --add remote.github.fetch '+refs/pull/*/head:refs/remotes/github/pr/*'
git fetch github
git switch -c pr-42 github/pr/42      # test
git switch main && git merge --no-ff pr-42
git push origin main                   # Gitea -> mirror -> GitHub
```

GitHub auto-closes a PR as merged once its head commit becomes an ancestor of the
base branch, so `--no-ff` — which preserves the contributor's SHAs — makes the PR
close itself when the mirror pushes. **For external PRs, merge; do not squash or
rebase.** Squashing rewrites the SHAs, the auto-close never fires, and closing by
hand reads to a first-time contributor as rejection.

`CONTRIBUTING.md` states this, and a GitHub Action comments it on incoming PRs.
No CLA; no DCO.

## Verification

The release is not done until all of these pass:

1. `R CMD check --as-cran` clean on Linux, and on Windows and macOS via the
   GitHub matrix. This package has never been checked on the latter two.
2. Full test suite (28 files) green against the **bundled fixture**, offline,
   with no credentials — the property public CI depends on.
3. Full test suite green against the **live corpus**, which additionally
   exercises the enumeration fix that the fixture's local path cannot.
4. `pkgdown::build_site()` completes.
5. Both vignettes present in the built tarball and
   `vignette("total-spending", package = "uscogdata")` resolves from an
   installed copy.
6. **Cold-start check on a machine that has never seen this package:** install
   from r-universe, `library(uscogdata)`, run the README quickstart verbatim with
   no environment variables set. This is the only test that catches the P0 class
   of fault, and its absence is why the fault survived.
7. End-to-end verb latency re-measured against the live corpus and the README's
   numbers updated if they moved.

## Out of scope

- **Corrections intake.** Deferred by decision. Consequence: the release cannot
  invite data-error reports or make the "traceable and correctable" claim that
  most distinguishes this corpus from Census's own files. `BugReports:` points at
  package issues only. A verified correction should eventually terminate as a
  `lineage_event` or `series_break` row so it propagates through provenance to
  every consumer — that design is unstarted.
- **Announcement posts.** Deferred. The API announcement is gated on corrections
  landing and merits a Civic Pulse edition.
- **The rest of the R package backlog.** Parked until this one completes the path.
- **`cog_pipeline` publication.** Stays private.
