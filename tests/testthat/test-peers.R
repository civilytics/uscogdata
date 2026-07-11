test_that("cog_find_peers returns same-type peers in the default pop band", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191")                # Broward County
  expect_s3_class(peers, "tbl_df")
  expected_cols <- c("canonical_govid", "gov_name", "fips_state",
                     "population", "pop_ratio", "rank")
  expect_true(all(expected_cols %in% names(peers)))
  expect_true(all(peers$pop_ratio >= 0.7 & peers$pop_ratio <= 1.3))
  expect_false("121011212191" %in% peers$canonical_govid)
  expect_equal(peers$rank, seq_len(nrow(peers)))
})

test_that("cog_find_peers respects same_state restriction", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191", same_state = TRUE,
                          pop_range = c(0.1, 10))
  expect_true(all(peers$fips_state == "12"))
})

test_that("cog_find_peers absolute pop range works", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191",
                          pop_range = c(1.5e6, 2.5e6),
                          is_ratio = FALSE, max_peers = 20L)
  expect_true(all(peers$population >= 1.5e6 &
                  peers$population <= 2.5e6))
})

test_that("cog_find_peers errors cleanly on unknown govid", {
  skip_if_no_corpus()
  expect_error(cog_find_peers("XXXINVALID"), "not found")
})

test_that("cog_peer_compare accepts a cog_find_peers result directly", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191", max_peers = 4L)
  r <- cog_peer_compare("121011212191", peers, "Police", years = 2020L)
  expect_s3_class(r, "tbl_df")
  expect_true("role" %in% names(r))
  expect_setequal(
    unique(r$role),
    c("target", "peer", "summary_p25", "summary_p50", "summary_p75")
  )
  expect_equal(sum(r$role == "target" & r$spend_subtype == "operations"), 1L)
})

test_that("cog_peer_compare accepts a character vector of govids", {
  skip_if_no_corpus()
  r <- cog_peer_compare(
    "121011212191",
    peers = c("481029175853", "481439135072"),     # Bexar, Tarrant
    category = "Police", years = 2020L
  )
  expect_true("peer" %in% r$role)
  expect_equal(sum(r$role == "peer" & r$spend_subtype == "operations"), 2L)
})

test_that("cog_peer_compare summary rows use real per-capita when requested", {
  skip_if_no_corpus()
  r <- cog_peer_compare(
    "121011212191",
    peers = c("481029175853", "481439135072", "261163166615"),
    category = "Police", years = 2019:2020,
    per_capita = TRUE, adjust_to_year = 2022L
  )
  summaries <- dplyr::filter(r, grepl("^summary_", role))
  expect_true(all(is.finite(summaries$amt_per_capita_real)))
  # summary rows have NA canonical_govid and named gov_name
  expect_true(all(is.na(summaries$canonical_govid)))
  expect_true(all(grepl("Peer", summaries$gov_name)))
})

test_that("cog_peer_compare provenance reports the outer verb + peer count", {
  skip_if_no_corpus()
  r <- cog_peer_compare("121011212191",
                        peers = c("481029175853", "481439135072"),
                        category = "Police", years = 2020L)
  prov <- attr(r, "provenance")
  expect_equal(prov$verb, "cog_peer_compare")
  expect_equal(prov$peer_count, 2L)
})

test_that("cog_peer_compare handles zero peers gracefully", {
  skip_if_no_corpus()
  r <- cog_peer_compare("121011212191",
                        peers = character(0),
                        category = "Police", years = 2020L)
  expect_true(all(r$role == "target"))
  expect_equal(sum(grepl("^summary_", r$role)), 0L)
})

test_that("cog_find_peers defaults `year` to most recent observed year for target", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191")
  expect_equal(attr(peers, "cohort_year"), 2020L)
  # Returned column is now `population`, not `population_acs`
  expect_true("population" %in% names(peers))
  expect_false("population_acs" %in% names(peers))
})

test_that("cog_find_peers honors an explicit `year`", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191", year = 2019L)
  expect_equal(attr(peers, "cohort_year"), 2019L)
})

test_that("cog_find_peers errors when target has no observed pop in `year`", {
  skip_if_no_corpus()
  expect_error(
    cog_find_peers("121011212191", year = 1999L),
    "no observed population"
  )
})

test_that("cog_peer_compare stamps cohort_year from peers attribute", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191", year = 2019L, max_peers = 4L,
                          pop_range = c(0.5, 1.5))
  r <- cog_peer_compare("121011212191", peers, "Police", years = 2020L)
  expect_true("cohort_year" %in% names(r))
  expect_true(all(r$cohort_year == 2019L))
  prov <- attr(r, "provenance")
  expect_equal(prov$cohort_year, 2019L)
  expect_equal(length(prov$cohort_govids), nrow(peers))
  # pop_range and is_ratio propagate from cog_find_peers attrs
  expect_equal(prov$pop_range, c(0.5, 1.5))
  expect_true(prov$is_ratio)
})

test_that("cog_peer_compare cohort_year is NA for bare character peers", {
  skip_if_no_corpus()
  r <- cog_peer_compare(
    "121011212191",
    peers = c("481029175853", "481439135072"),
    category = "Police", years = 2020L
  )
  expect_true(all(is.na(r$cohort_year)))
})
