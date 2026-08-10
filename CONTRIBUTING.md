# Contributing to uscogdata

Thanks for reading this — a package like this gets better mostly through people
noticing that a number looks wrong.

## Where the code lives

Development happens on **Gitea**, at
`gitea.civilytics.org/Civilytics/uscogdata`. The repository at
`github.com/civilytics/uscogdata` is a **mirror** that accepts issues and pull
requests.

## What happens to a GitHub pull request

Open it normally. Behind the scenes it is fetched and landed on the canonical
Gitea repository, then syncs back:

```sh
git fetch github refs/pull/42/head:pr-42
git switch main && git merge --no-ff pr-42
git push origin main            # Gitea -> mirror -> GitHub
```

Because the merge preserves your commits at their original SHAs, **GitHub marks
your PR merged on its own** as soon as the mirror syncs. So:

> If your pull request closes as "Merged" without anyone visibly clicking
> Merge, that is the normal, successful outcome — not a rejection.

Substantial contributions get a `ctb` entry in `DESCRIPTION`, which surfaces in
`citation("uscogdata")`.

There is no CLA and no DCO sign-off requirement.

## Running the tests

```r
devtools::test()   # bundled fixture; no network, no credentials
```

`tests/testthat/setup.R` points `USCOGDATA_URL` at
`inst/extdata/fixture_corpus/` automatically — a four-year slice (2011, 2012,
2019, 2020) covering all 50 states. That is the whole data setup.

## Testing against the live corpus

```sh
USCOGDATA_LIVE_TEST=true Rscript -e 'devtools::test(filter = "live-corpus")'
```

This is worth understanding rather than skipping. Until 0.3.0 the package
**could not read a remote corpus at all** — the partitioned view used a glob,
and DuckDB cannot expand a glob over generic HTTP. It went unnoticed for months
because every test path used a local corpus (the bundled fixture), and so did
the production API (a host mount). Nothing exercised the package the way a new
user does.

`test-live-corpus.R` is the only test that runs with no `USCOGDATA_URL`, no
option, and no fixture. If you change anything touching view registration,
manifest handling, or configuration, run it.

## Do not exclude the fixture from the build

There is a temptation to add `^inst/extdata/fixture_corpus$` to
`.Rbuildignore` because 15 MB feels large for a package. Don't:

- `vignette("total-spending")` reads from it and would fail to build.
- `R CMD check` on r-universe and GitHub Actions would have no corpus, so the
  suite could not run without credentials.

This package is not going to CRAN, so its 5 MB guidance does not apply. A
package-size NOTE in `R CMD check` is expected and acceptable.

## Downstream consumers

`cog-api` depends on this package and its CI clones uscogdata at
`USCOGDATA_REF`, **defaulting to `main`**. There is no pin. Anything merged
here reaches the API's next build, so before merging a change to the reader,
run the API suite against your branch:

```sh
Rscript -e "remotes::install_local('/path/to/uscogdata', upgrade = 'never')"
cd /path/to/cog-api/api/tests/testthat
Rscript -e 'testthat::test_dir(".", stop_on_failure = TRUE)'
```

The API calls only exported verbs, so internal refactors are usually safe —
but "usually" is not a release gate.

## Release checklist

1. `devtools::test()` — green against the bundled fixture, offline.
2. `USCOGDATA_LIVE_TEST=true devtools::test()` — green against the live corpus.
3. cog-api suite green against this branch (above).
4. `devtools::check(args = "--as-cran")` — 0 errors, 0 warnings.
5. `pkgdown::build_site()` completes.
6. Vignettes resolve from an installed copy:
   `vignette("total-spending", package = "uscogdata")`.
7. **Cold-start check**: on a machine that has never had this package,
   install it and run the README quickstart verbatim with no environment
   variables set. This is the only check that catches a
   corpus-unreachable defect, and its absence is why 0.3.0 needed fixing.
8. Bump `Version` and add a `NEWS.md` section.
9. Tag on **Gitea** (`git tag -a vX.Y.Z && git push origin vX.Y.Z`). The mirror
   workflow carries tags to GitHub on its own — confirm the tag appears at
   `github.com/civilytics/uscogdata/tags` before continuing.
10. Update the r-universe registry pin at
    `github.com/civilytics/civilytics.r-universe.dev` — edit `packages.json`'s
    `branch` to the new tag. **r-universe will not pick up a release until this
    is edited**: the pin is a tag, deliberately, so a mid-refactor `main` is
    never published as a release. `"branch": "*release"` would track releases
    automatically, but it needs a GitHub *Release* object and the mirror pushes
    tags only — so it would silently never update.
