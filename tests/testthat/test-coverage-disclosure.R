# Madison walkthrough audit -- findings F-020 and F-023. Tracked as uscogdata#13.
# See docs/walkthroughs/FINDINGS.md in cog_explorer.
#
# The owner's settled design (2026-07-28): a `coverage` argument on
# cog_geographic_rollup(), cog_find_peers()/cog_peer_compare() and their
# cog-api equivalents --
#   "all"        every unit that reported that year (today's behaviour, DEFAULT)
#   "census"     census years only (years ending 2 or 7)
#   "consistent" only units reporting in every requested year (balanced panel)
# -- PLUS always-on coverage metadata on every result regardless of mode:
# n_units_reporting, n_units_expected, is_census_year.
#
# Motivating principle: using these verbs correctly must not require the user to
# know that the Census of Governments is a complete census only in years ending
# in 2 and 7.
#
# The helper below accepts that metadata either as columns on the returned
# tibble or as a per-year table in provenance$coverage -- the design fixes the
# three field names and that they reach the caller, not the container.

wt_coverage <- function(x) {
  prov <- attr(x, "provenance")
  cov <- prov$coverage
  if (is.null(cov)) {
    needed <- c("year", "n_units_reporting", "n_units_expected", "is_census_year")
    expect_true(all(needed %in% names(x)))
    cov <- unique(x[, needed])
  }
  cov[order(cov$year), ]
}

test_that("multi-government aggregates disclose reporting coverage on every result", {
  testthat::skip("Blocked on uscogdata#13 (findings F-020, F-023)")

  # -- F-020: geographic rollups -------------------------------------------
  # Wisconsin's city/village universe is 608 governments. On the bundled
  # fixture, FY2012 (a census year) has 597 of them reporting while FY2019 and
  # FY2020 (sample years) have 112 and 114 -- an 18%-98% swing that today's
  # return value says nothing about. Counts cross-checked against the raw
  # corpus, not through cog_geographic_rollup(), which is under test.
  wi <- cog_gov_search(name = NULL, state = "WI", type = "city")
  expect_equal(nrow(wi), 608L)

  roll <- cog_geographic_rollup(govids = list(city = wi$canonical_govid),
                                category = NULL, years = c(2011L, 2012L, 2019L, 2020L))
  cov <- wt_coverage(roll)

  expect_equal(cov$n_units_expected, rep(608L, 4L))
  expect_equal(cov$n_units_reporting, c(152L, 597L, 112L, 114L))
  expect_equal(cov$is_census_year, c(FALSE, TRUE, FALSE, FALSE))

  raw_2012 <- wt_raw_query(paste0(
    "SELECT COUNT(DISTINCT canonical_govid) n FROM read_parquet('", wt_corpus_glob(), "') ",
    "WHERE type = 2 AND fips_state = 55 AND year = 2012 ",
    "AND LEFT(item_code, 1) IN ('E','F','G') AND NOT is_aggregate"))
  expect_equal(cov$n_units_reporting[cov$year == 2012], as.integer(raw_2012$n[[1]]))

  # -- F-023: peer cohorts --------------------------------------------------
  # CHILTON CITY, WI (ACS population 4,017): a 15-peer cohort fixed at FY2012
  # reports 15 of 15 in FY2012 and only 3 of 15 in FY2019 and FY2020. Nothing
  # in cog_peer_compare()'s return distinguishes those years today.
  chilton <- "552015177095"
  peers <- cog_find_peers(chilton, year = 2012L, max_peers = 15L)
  expect_equal(nrow(peers), 15L)

  cmp <- cog_peer_compare(target_govid = chilton, peers = peers, category = NULL,
                          years = c(2012L, 2019L, 2020L), per_capita = TRUE)
  cov_peers <- wt_coverage(cmp)
  expect_equal(cov_peers$n_units_expected, rep(15L, 3L))
  expect_equal(cov_peers$n_units_reporting, c(15L, 3L, 3L))
  expect_equal(cov_peers$is_census_year, c(TRUE, FALSE, FALSE))

  # -- the three coverage modes --------------------------------------------
  expect_equal(attr(cog_peer_compare(target_govid = chilton, peers = peers,
                                     category = NULL, years = c(2012L, 2019L, 2020L),
                                     per_capita = TRUE),
                    "provenance")$coverage_mode, "all")     # unchanged default

  consistent <- cog_peer_compare(target_govid = chilton, peers = peers,
                                 category = NULL, years = c(2012L, 2019L, 2020L),
                                 per_capita = TRUE, coverage = "consistent")
  n_by_year <- tapply(consistent$canonical_govid[consistent$role == "peer"],
                      consistent$year[consistent$role == "peer"],
                      function(g) length(unique(g)))
  expect_equal(unname(as.integer(n_by_year)), c(3L, 3L, 3L))  # balanced panel

  census_only <- cog_geographic_rollup(govids = list(city = wi$canonical_govid),
                                       category = NULL,
                                       years = c(2011L, 2012L, 2019L, 2020L),
                                       coverage = "census")
  expect_equal(sort(unique(census_only$year)), 2012)
})
