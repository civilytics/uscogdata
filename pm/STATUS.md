# Project status

> Between the compass markers is generated. Edit the sources, not this.

<!-- compass:begin -->
<!-- compass:board -->

## Where this stands

uscogdata is at 0.4.0 and its public surface is settled: the query verbs, the cohort
predicates added in this release, and the provenance contract every verb returns.

The six open issues split cleanly. Two are API work carried out of the #9 review pass
and deliberately deferred there rather than fixed in that branch. Three concern the
corpus layer, and the largest of them, partition-level caching, was named the single
highest-leverage change on the remote path before being deferred. One, the
data-correction intake (#52), is a decision rather than a task: it was parked during
the 0.3.0 design, and the API announcement waits on it, because without it the corpus
cannot make the "traceable and correctable" claim that most distinguishes it from
Census's own files.

Nothing here is blocked on anything else, so the ordering is a judgement about value
rather than a dependency graph.

Compass's own files moved out of `docs/` this session. They were sitting inside
pkgdown's output directory, and `pkgdown::clean_site()` deletes every top-level entry
there except `CNAME` and `dev` — asked directly, it listed `docs/pm` and
`docs/decisions` among the 28 it would remove, with the guard that would have stopped
it satisfied by `docs/pkgdown.yml`. They are in `pm/` now. Nothing was lost: the
journal had no entries and there were no decision records yet, which made this the
cheapest moment to move. The `.gitignore` workaround that re-included two children of
an excluded `docs/` is gone with it.

## Ready to work on next

- **#34** cog_revenue() offers expenditure recipes as suggestions: scope the candidate query by category_type · `ws/api` — nothing is blocking it; something is currently wrong
- **#36** n_units_reporting is category-conditional and cannot be read as a response rate · `ws/corpus` — nothing is blocking it; owed work from an earlier change
- **#2** Extend population data to be households as an alternate spending denominator · `ws/corpus` — nothing is blocking it
- **#33** Decompose .build_suggestions() (106 lines) into named helpers · `ws/api` — nothing is blocking it
- **#52** Release 11/11: design the data-correction intake (deferred; gates the API announcement) · `ws/corpus` — nothing is blocking it
- **#64** Partition-level caching: R/cache.R is still a stub, and the remote path pays for it every session · `ws/corpus` — nothing is blocking it

## Workstreams

| Stream | Commits since | Open | Debt | Owes docs |
|---|---|---|---|---|
| Query verbs and results | 77 | 2 | 0 | no |
| Corpus, mirror, provenance | 39 | 4 | 1 | no |
| Vignettes and guides | 34 | 0 | 0 | **yes** |

## CI

![R-CMD-check](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/ci.yml/badge.svg?branch=main)
![Mirror to GitHub](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/mirror-github.yml/badge.svg?branch=main)

<details>
<summary>Dependency graph and detail</summary>

_Nothing blocks anything else, so there is no graph to draw._

- Marker: `none` (no journal entry yet)
- Commits since: 165
- Open issues: 6

</details>

<!-- compass:end -->
