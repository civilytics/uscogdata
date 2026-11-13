# Project status

> Between the compass markers is generated. Edit the sources, not this.

<!-- compass:begin -->
<!-- compass:board -->

## Where this stands

uscogdata reads the public Census of Governments finance corpus from R. A remote session now opens in under half a second after the first, because the package keeps the small metadata tables on disk and checks them against the manifest. The yearly data is still read remotely, and `cog_mirror()` is still the fastest way to do heavy work. Rows can carry the months each survey year covers; the cog-api half of that (#77) is still open. Fifty-eight governments keep Census's "NOT AVAILABLE" name, and eight more get their real names back with the next corpus publish (#76).

## Ready to work on next

- **#83** cog_mirror() records a file as downloaded without checking its sha256 · `ws/corpus` — nothing is blocking it; something is currently wrong
- **#2** Extend population data to be households as an alternate spending denominator · `ws/corpus` — nothing is blocking it
- **#77** Expose fiscal-year timing: what months each survey year covers, per government · `ws/api` — nothing is blocking it
- **#76** 66 governments in the roster are named NOT AVAILABLE, so no search by name can find them · `ws/corpus` — waiting on a person, not on other work
- **#74** CLAUDE.md's Current State section is frozen at 2026-08-03 · `ws/docs` — waiting on a person, not on other work
- **#52** Release 11/11: design the data-correction intake (deferred; gates the API announcement) · `ws/corpus` — waiting on a person, not on other work

## Workstreams

| Stream | Commits since | Open | Debt | Owes docs |
|---|---|---|---|---|
| Query verbs and results | 5 | 1 | 0 | no |
| Corpus, mirror, provenance | 5 | 4 | 0 | no |
| Vignettes and guides | 9 | 1 | 1 | no |

## CI

![R-CMD-check](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/ci.yml/badge.svg?branch=main)
![Mirror to GitHub](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/mirror-github.yml/badge.svg?branch=main)

<details>
<summary>Dependency graph and detail</summary>

_Nothing blocks anything else, so there is no graph to draw._

- Marker: `ba57f9cb` (2026-09-30)
- Commits since: 15
- Open issues: 6

</details>

<!-- compass:end -->
