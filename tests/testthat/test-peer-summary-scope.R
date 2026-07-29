# Madison walkthrough audit -- finding F-021. Tracked as uscogdata#14.
# See docs/walkthroughs/FINDINGS.md in cog_explorer.
#
# .peer_summary_rows() computes stats::quantile() separately INSIDE each
# (year, spend_subtype, category) cell. A summary_p50 row is therefore "the
# median peer's value in that one category", not "the value of the median
# peer's total". Summing those rows across categories -- the obvious move for a
# caller who wants one peer-median total line and reads only the column names --
# misstated a total-spending band by -32.7% to +251.0% across the 24 years the
# audit tested, with a sign flip at FY2012.
#
# The verb is not wrong and its documented use (faceting by role AND category)
# is unaffected, so the fix is documentation: one sentence in @return.

test_that("cog_peer_compare() documents that summary_* rows are per-category quantiles", {
  testthat::skip("Blocked on uscogdata#14 (finding F-021)")

  rd <- paste(readLines(testthat::test_path("..", "..", "man", "cog_peer_compare.Rd"),
                        warn = FALSE), collapse = " ")

  # The @return section must say the quantile is computed within each cell...
  expect_match(rd, "within each|per-category|per category", ignore.case = TRUE)
  # ...and must warn that the rows are not additive across category.
  expect_match(rd, "not additive|do(es)? not sum|cannot be summed", ignore.case = TRUE)
  # ...naming the grouping explicitly.
  expect_match(rd, "spend_subtype", fixed = TRUE)

  # Pin the mechanism numerically so a future refactor that quietly changes the
  # quantile grouping fails here rather than silently invalidating the sentence
  # above. Fixture: Madison, 10 peers found at FY2020, category = NULL.
  peers <- cog_find_peers("552025209777", year = 2020L, max_peers = 10L)
  cmp <- cog_peer_compare(target_govid = "552025209777", peers = peers,
                          category = NULL, years = 2020L, per_capita = TRUE)

  naive <- sum(cmp$amt_per_capita_nominal[cmp$role == "summary_p50"], na.rm = TRUE)

  peer_rows <- cmp[cmp$role == "peer", ]
  per_gov <- tapply(peer_rows$amt_per_capita_nominal, peer_rows$canonical_govid,
                    sum, na.rm = TRUE)
  correct <- unname(stats::quantile(per_gov, 0.5, na.rm = TRUE))

  expect_equal(round(naive), 6180)     # summing the built-in summary rows
  expect_equal(round(correct), 2043)   # quantile of each peer's OWN total
  expect_gt(naive / correct, 2)        # a +200% misstatement on this cohort
})
