# Madison walkthrough audit -- finding F-004. Tracked as uscogdata#15.
# See docs/walkthroughs/FINDINGS.md in cog_explorer.
#
# The raw Census files report thousands of dollars; this package multiplies by
# 1000 and returns full US dollars. That is the friendlier choice and is not
# wrong -- but cog_explorer's CLAUDE.md states "All raw `amt` values are in
# $1,000s", so a reader who applies that rule to amt_nominal overstates every
# figure by 1000x, and gets a plausible-looking number rather than an obvious
# error. The audit rates this the highest-consequence definitional gap it found.
#
# Deliberately NOT asserted here: man/cog_spending.Rd and man/cog_revenue.Rd,
# which ALREADY carry the statement in their @return sections (verified
# 2026-07-29), as does cog-api's data-dictionary.md (since 2b71b41). The gap is
# in the surfaces a reader meets first and in cog_explorer's own conventions
# doc -- see uscogdata#15 for the full surface-by-surface table and for the two
# secondary tasks (cog_explorer/CLAUDE.md, which has no git remote, and
# cog-api's llms.txt, which is silent on units).

test_that("returned amounts are documented as full US dollars where readers meet the package", {

  # README and vignettes ship only in the source tree, not in the installed
  # package, so these assertions cannot run under R CMD check -- CI's earlier
  # testthat::test_local() step is what enforces them. See
  # skip_if_no_source_tree() in helper-fixture.R.
  docs <- skip_if_no_source_tree(
    "README.md",
    c("vignettes", "total-spending.Rmd"),
    c("vignettes", "population-denominators.Rmd")
  )

  says_units <- function(path) {
    txt <- paste(readLines(path, warn = FALSE), collapse = " ")
    grepl("full US dollars|full U\\.S\\. dollars", txt, ignore.case = TRUE) &&
      grepl("\\$1,000s|thousands of dollars", txt, ignore.case = TRUE)
  }

  for (path in docs) expect_true(says_units(path))

  # Pin the documented claim to the actual behaviour, so the two cannot drift.
  # The expected raw amount is read straight from the corpus's parquet
  # partitions -- never through cog_spending(), which is the thing being
  # described. Madison FY2020: E/F/G = 623,347 ($1,000s) -> $623,347,000.
  raw_thousands <- wt_raw_amt("552025209777", 2020L, prefixes = c("E", "F", "G"))
  expect_equal(raw_thousands, 623347)

  returned <- cog_spending(govid = "552025209777", years = 2020L)
  expect_equal(sum(returned$amt_nominal), raw_thousands * 1000)

  units <- attr(returned, "provenance")$transformations$units_conversion
  expect_true(units$applied)
  expect_equal(units$multiplier, 1000)
})
