# Project status

> Between the compass markers is generated. Edit the sources, not this.

<!-- compass:begin -->
<!-- compass:board -->

## Where this stands

uscogdata's code now lives only in Gitea; the old Nextcloud folder keeps just build
output and working files. The move changed no test result: 1,101 pass and the two
opt-in live-corpus tests skip, before and after. It turned up one defect, #73: the
fixture's reference docs have never been in git, because a `.gitignore` rule matches
too broadly. Next in line are #73 and #72 (a vignette for the coverage counters), with
#52 (data-correction intake) and #74 (the stale state section in `CLAUDE.md`) waiting
on a decision.

## Ready to work on next

- **#73** The fixture corpus's docs/ never reaches git: .gitignore's docs/ rule is unanchored · `ws/corpus` — nothing is blocking it; something is currently wrong
- **#72** docs: add a vignette explaining provenance$coverage counters · `ws/docs` — nothing is blocking it; owed work from an earlier change
- **#2** Extend population data to be households as an alternate spending denominator · `ws/corpus` — nothing is blocking it
- **#64** Partition-level caching: R/cache.R is still a stub, and the remote path pays for it every session · `ws/corpus` — nothing is blocking it
- **#74** CLAUDE.md's Current State section is frozen at 2026-08-03 · `ws/docs` — waiting on a person, not on other work
- **#52** Release 11/11: design the data-correction intake (deferred; gates the API announcement) · `ws/corpus` — waiting on a person, not on other work

## Workstreams

| Stream | Commits since | Open | Debt | Owes docs |
|---|---|---|---|---|
| Query verbs and results | 0 | 0 | 0 | no |
| Corpus, mirror, provenance | 0 | 4 | 0 | no |
| Vignettes and guides | 0 | 2 | 2 | no |

## CI

![R-CMD-check](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/ci.yml/badge.svg?branch=main)
![Mirror to GitHub](https://gitea.civilytics.org/Civilytics/uscogdata/actions/workflows/mirror-github.yml/badge.svg?branch=main)

<details>
<summary>Dependency graph and detail</summary>

_Nothing blocks anything else, so there is no graph to draw._

- Marker: `9adb9211` (2026-09-09)
- Commits since: 3
- Open issues: 6

</details>

<!-- compass:end -->
