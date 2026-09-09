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

  # uscogdata#36: with category = NULL (no category scope), "reported at
  # all" and "collected" are the same question, so n_units_collected must
  # equal n_units_reporting exactly here. This case alone cannot catch a
  # regression in HOW n_units_collected is computed, though: see the
  # category-scoped test below for that.
  expect_equal(cov$n_units_collected, cov$n_units_reporting)

  # Cross-check against the raw partitions, scoped to the SAME universe the
  # rollup was given -- the 608 govids above. Scoping instead on the long
  # table's own `type`/`fips_state` asks a different question and answers 595:
  # VERNON VILLAGE and WAUKESHA VILLAGE carry type = 3 there (their as-of-year
  # identity, when they were townships) while the xwalk lists them as
  # govs_type = 2 (their present identity, as villages). Schema v6 made the
  # long table's geography present-harmonized and moved as-of-year to the
  # *_asof columns, but `type` still reads as-of-year -- see .validate_schema()
  # in R/manifest.R. n_units_reporting counts against the requested universe,
  # so 597 is the number that answers "how many of the governments I asked
  # about reported".
  raw_2012 <- wt_raw_query(paste0(
    "SELECT COUNT(DISTINCT canonical_govid) n FROM read_parquet('", wt_corpus_glob(), "') ",
    "WHERE year = 2012 AND LEFT(item_code, 1) IN ('E','F','G') AND NOT is_aggregate ",
    "AND canonical_govid IN (",
    paste0("'", wi$canonical_govid, "'", collapse = ","), ")"))
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
  # uscogdata#36: same identity as the rollup case above, category = NULL.
  expect_equal(cov_peers$n_units_collected, cov_peers$n_units_reporting)

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

test_that("n_units_collected separates sampling from real zeros, category-scoped (uscogdata#36)", {
  # The motivating case from the issue: Wisconsin cities, category = "Police".
  # FY2012 is a complete census year -- collection is not partial -- yet a
  # category-conditional n_units_reporting alone reads like a sampling gap.
  # n_units_collected must diverge from n_units_reporting here, unlike the
  # category = NULL cases above, because most of the FY2012 gap is cities
  # that contract policing to the county sheriff (collected, real zero), not
  # cities Census never surveyed.
  wi <- cog_gov_search(name = NULL, state = "WI", type = "city")
  roll <- suppressMessages(cog_geographic_rollup(
    govids = list(city = wi$canonical_govid), category = "Police",
    years = c(2011L, 2012L, 2019L, 2020L)))
  cov <- wt_coverage(roll)

  expect_equal(cov$n_units_expected, rep(608L, 4L))
  expect_equal(cov$n_units_collected, c(152L, 597L, 112L, 114L))
  expect_equal(cov$n_units_reporting, c(152L, 485L, 109L, 111L))

  # The pair the issue actually wants: collected/expected is the true
  # collection rate (98% in the FY2012 census year, matching the raw
  # cross-check above); reporting/collected is category participation among
  # collected units (81% -- most of the gap is real, not sampling).
  expect_equal(round(cov$n_units_collected[cov$year == 2012] /
                        cov$n_units_expected[cov$year == 2012], 2), 0.98)
  expect_equal(round(cov$n_units_reporting[cov$year == 2012] /
                        cov$n_units_collected[cov$year == 2012], 2), 0.81)

  # Every year: collected is bounded between reporting and expected.
  expect_true(all(cov$n_units_collected >= cov$n_units_reporting))
  expect_true(all(cov$n_units_collected <= cov$n_units_expected))
})

test_that(".coverage_table() candidates a government collected-but-absent from the category result (uscogdata#36)", {
  # Direct regression test for the mechanism itself: n_units_collected's
  # candidate list must be the caller's full expected cohort (expected_ids),
  # never derived from `result`/`rows`. A government with zero rows in the
  # requested category across every requested year never appears in
  # `result` at all, so deriving candidates from `result` would silently
  # drop exactly the "collected but real zero" governments this counter
  # exists to count -- collapsing it back to n_units_reporting.
  con <- uscogdata:::.ensure_session()

  # A real fixture govid, present in spending_long_harmonized for 2019 (in
  # SOME category), but absent from this fake category-specific `result`.
  govid <- "011021100004"
  fake_result <- data.frame(canonical_govid = character(0), year = integer(0))

  cov <- uscogdata:::.coverage_table(
    fake_result, years = 2019L, n_expected = 1L,
    con = con, long_view = "spending_long_harmonized",
    expected_ids = govid
  )
  expect_equal(cov$n_units_collected, 1L)
  expect_equal(cov$n_units_reporting, 0L)

  # Without a connection, long_view, or expected_ids, the lookup is skipped
  # rather than silently wrong.
  no_con <- uscogdata:::.coverage_table(fake_result, years = 2019L, n_expected = 1L)
  expect_true(is.na(no_con$n_units_collected))

  no_ids <- uscogdata:::.coverage_table(
    fake_result, years = 2019L, n_expected = 1L,
    con = con, long_view = "spending_long_harmonized"
  )
  expect_true(is.na(no_ids$n_units_collected))
})

test_that("n_units_collected uses the resolved basis's long view, not a hardcoded harmonized one (uscogdata#36)", {
  # spending_long_harmonized only exists when schema_version >= 5 (R/views.R
  # gates the harmonization views on it); on an older corpus cog_spending()
  # resolves basis = "raw" and queries spending_long instead. The coverage
  # lookup must follow the SAME resolved basis, not a literal
  # "spending_long_harmonized", or it hard-errors with a DuckDB catalog
  # error on every schema_version < 5 corpus -- a vintage the package
  # otherwise explicitly still supports (see test-manifest.R's dual-accept
  # tests).
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    con <- cog_open()
    ids <- DBI::dbGetQuery(con,
      "SELECT DISTINCT canonical_govid FROM spending_long WHERE year = 2011 LIMIT 3"
    )$canonical_govid
    expect_gte(length(ids), 3L)

    roll <- suppressMessages(cog_geographic_rollup(
      list(city = ids), category = NULL, years = 2011L))
    expect_equal(attr(roll, "provenance")$basis, "raw")
    cov <- attr(roll, "provenance")$coverage
    expect_false(is.na(cov$n_units_collected))
    expect_equal(cov$n_units_collected, length(ids))

    cmp <- suppressMessages(cog_peer_compare(
      target_govid = ids[1], peers = ids[-1], category = NULL, years = 2011L))
    expect_equal(attr(cmp, "provenance")$basis, "raw")
    cov_peers <- attr(cmp, "provenance")$coverage
    expect_false(is.na(cov_peers$n_units_collected))
  })
})
