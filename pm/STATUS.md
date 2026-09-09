# Project status

> Between the compass markers is generated. Edit the sources, not this.

<!-- compass:begin -->
<!-- compass:board -->

## Where this stands

Three pieces of work landed and merged this session: the #33/#34 split (a pure
decomposition and a behavior fix, now independently tested and reviewed), and
#36 (the second `n_units_collected` coverage counter), which turned up two
real bugs -- a scoping leak and a hardcoded view name -- before either
shipped. All three issues are closed, CI is green on `main`, and a roborev
review pass on the intermediate commits caught one more small documentation
drop, now restored. One new issue (#72) tracks a coverage vignette that
neither existing walkthrough covers.

## Ready to work on next

- **#72** docs: add a vignette explaining provenance$coverage counters · `ws/docs` — nothing is blocking it; owed work from an earlier change
- **#2** Extend population data to be households as an alternate spending denominator · `ws/corpus` — nothing is blocking it
- **#64** Partition-level caching: R/cache.R is still a stub, and the remote path pays for it every session · `ws/corpus` — nothing is blocking it
- **#52** Release 11/11: design the data-correction intake (deferred; gates the API announcement) · `ws/corpus` — waiting on a person, not on other work

## Workstreams

| Stream | Commits since | Open | Debt | Owes docs |
|---|---|---|---|---|
| Query verbs and results | 5 | 0 | 0 | no |
| Corpus, mirror, provenance | 1 | 3 | 0 | **yes** |
| Vignettes and guides | 1 | 1 | 1 | **yes** |

## CI

![R-CMD-check](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/ci.yml/badge.svg?branch=main)
![Mirror to GitHub](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/mirror-github.yml/badge.svg?branch=main)

<details>
<summary>Dependency graph and detail</summary>

_Nothing blocks anything else, so there is no graph to draw._

- Marker: `1ec20174` (2026-08-23)
- Commits since: 7
- Open issues: 4

</details>

<!-- compass:end -->
