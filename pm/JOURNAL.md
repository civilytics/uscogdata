# Project journal

Append-only, newest first. **Entries are never edited** — the value of this file is
that it records what was believed at the time, including the parts that turned out
wrong. Where things stand *today* is in `STATUS.md`, which is generated.

Four lines per entry. The analysis belongs in the issue or the decision record; this
file carries the reasoning and the pointers.

- **Why** — the driver. The one line git cannot reconstruct later.
- **Obligates** — issues this change created elsewhere. Numbers, not prose.
- **Refs** — commits, issues, decision records.

---

## 2026-11-12 · corpus · remote sessions open in 0.4 s; fixture docs tracked; 8 names recovered upstream

**Why:** Every remote session re-requested the same file metadata and re-read the same 3 MB of metadata tables. Caching both, with the tables checked against the manifest's sha256, cut session open from 5.6 s to 0.4 s after the first session. The missing names are Census's own placeholder, so the fix, and the record of the 58 that can't be fixed, live in the pipeline.
**Obligates:** #83, #76 (waits on the next corpus publish)
**Refs:** #73, #64, 1ff6fe8, 455ae2f, 8b92ce3, census_of_governments_finance_pipeline#156 and its decision 0008

## 2026-11-04 · api · fiscal-year periods on the verbs; coverage suggestions exported (recorded 2026-11-12)

**Why:** A survey year runs up to 18 months ahead of the calendar for some governments, so `nss_time` couldn't place events against a series without knowing which months each row covers. FY1993 has no fiscal-year end for 99% of governments, and that gap is already in the Census file.
**Obligates:** #77 (the cog-api half), census_of_governments_finance_pipeline#129
**Refs:** #72, #75, #77, #78, #79, #80, b6b3e46, dc93eec, GitHub PRs 1–6

## 2026-09-30 · repo · moved out of Nextcloud; code syncs only through Gitea

**Why:** Nextcloud was syncing this repo's `.git`, which risks conflict copies inside
it and stalls the client's cold scan across dozens of repos. Nothing untracked is
data, so nothing is linked (`--no-data`); the move changed no test result (1,101
pass, 2 skip before and after).
**Obligates:** #73, #74
**Refs:** 4bedf85 (ci/apt-https pushed to clear the move's preflight), 63b421a

## 2026-09-09 · ci · Linux R-CMD-check legs unblocked (recorded 2026-09-30)

**Why:** GitHub's ubuntu-latest image carries a google-chrome apt source that
intermittently fails its own hash check, and setup-r's `apt-get update` died on it for
every R version; the source is now found by URL and removed, and the step fails
loudly if it survives.
**Obligates:** (none)
**Refs:** d83301b, d1165a5

## 2026-09-09 · model · #36 coverage counter finished, two bugs caught before merge

**Why:** the drafted n_units_collected fix (uncommitted) derived its candidate
cohort from category-filtered results instead of the caller's full expected
cohort, and hardcoded a view name absent below schema_version 5 -- both
silent on the fixture, both would have shipped without an independent review
pass before merge.
**Obligates:** #72
**Refs:** #36, b41d5ee, PR#71

## 2026-09-09 · model · #33/#34 split into independently-tested commits

**Why:** #33's own branch had its tests sitting uncommitted, and quietly bundled
a behavior change (#34) into what its commit message called a pure refactor;
splitting them let each pass CI with its own tests instead of merging on a
false "tests pass" claim.
**Obligates:** (none)
**Refs:** #33, #34, 0c7c7eb, 392643b, d0d724c, 9f5cd98, PR#69, PR#70
