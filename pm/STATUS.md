# Project status

> Between the compass markers is generated. Edit the sources, not this.

<!-- compass:begin -->
<!-- compass:board -->

## Where this stands

uscogdata reads the public Census of Governments finance corpus from R. A remote session now opens in under half a second after the first, because the package keeps the small metadata tables on disk and checks them against the manifest. Heavy work is still fastest through `cog_mirror()`, which doesn't yet check what it downloads (#83). Rows can carry the months each survey year covers; the cog-api half of that (#77) is still open. The corpus published on Nov 13 gives six formerly unnamed governments their names, and 60 keep Census's "NOT AVAILABLE".

## Ready to work on next

- **#83** cog_mirror() records a file as downloaded without checking its sha256 · `ws/corpus` — nothing is blocking it; something is currently wrong
- **#84** Low findings from the Nov 4 reviews: version-pinned messages, unstated vintages, cog_suggestions() edges · `ws/api` — nothing is blocking it; owed work from an earlier change
- **#2** Extend population data to be households as an alternate spending denominator · `ws/corpus` — nothing is blocking it
- **#77** Expose fiscal-year timing: what months each survey year covers, per government · `ws/api` — nothing is blocking it
- **#74** CLAUDE.md's Current State section is frozen at 2026-08-03 · `ws/docs` — waiting on a person, not on other work
- **#52** Release 11/11: design the data-correction intake (deferred; gates the API announcement) · `ws/corpus` — waiting on a person, not on other work

## Workstreams

| Stream | Commits since | Open | Debt | Owes docs |
|---|---|---|---|---|
| Query verbs and results | 0 | 2 | 1 | no |
| Corpus, mirror, provenance | 0 | 3 | 0 | no |
| Vignettes and guides | 0 | 1 | 1 | no |

## CI

![R-CMD-check](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/ci.yml/badge.svg?branch=main)
![Mirror to GitHub](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/mirror-github.yml/badge.svg?branch=main)

<details>
<summary>Dependency graph and detail</summary>

_Nothing blocks anything else, so there is no graph to draw._

- Marker: `441bfb2b` (2026-11-13)
- Commits since: 0
- Open issues: 6

</details>

<!-- compass:end -->
