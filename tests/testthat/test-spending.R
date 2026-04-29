test_that("cog_spending returns expected shape for Broward Corrections 2020", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", years = 2020L, category = "Corrections")
  expect_s3_class(r, "tbl_df")
  expected_cols <- c("year", "canonical_govid", "gov_name", "spend_subtype",
                     "category", "amt_nominal", "codes_included",
                     "aggregate_fallback", "notes")
  expect_true(all(expected_cols %in% names(r)))
  expect_equal(unique(r$canonical_govid), "101006006")
  expect_equal(unique(r$year), 2020L)
  expect_equal(unique(r$category), "Corrections")
  expect_true(all(r$spend_subtype %in% c("operations", "capital")))
  expect_true(all(r$amt_nominal > 0))
})

test_that("cog_spending vectorised years + categories", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2019:2020,
                    category = c("Corrections", "Police"))
  expect_true(all(r$year %in% 2019:2020))
  expect_true(all(r$category %in% c("Corrections", "Police")))
  expect_gte(nrow(r), 4L)
})

test_that("cog_spending with per_capita adds per-capita nominal column", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2020L, "Corrections", per_capita = TRUE)
  expect_true("amt_per_capita_nominal" %in% names(r))
  expect_false("amt_real" %in% names(r))
  expect_false("amt_per_capita_real" %in% names(r))
  expect_true(all(is.finite(r$amt_per_capita_nominal)))
  expect_true(all(r$amt_per_capita_nominal < r$amt_nominal))
})

test_that("cog_spending with adjust_to_year adds real column", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2019:2020, "Corrections",
                    adjust_to_year = 2022L)
  expect_true("amt_real" %in% names(r))
  r2019 <- dplyr::filter(r, year == 2019L)
  expect_true(any(r2019$amt_nominal != r2019$amt_real))
})

test_that("cog_spending with per_capita + adjust_to_year adds all columns", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2020L, "Corrections",
                    per_capita = TRUE, adjust_to_year = 2022L)
  expect_true(all(c("amt_nominal", "amt_real",
                    "amt_per_capita_nominal", "amt_per_capita_real") %in%
                  names(r)))
})

test_that("cog_spending for unknown govid returns empty tibble + informs", {
  skip_if_no_corpus()
  expect_message(
    r <- cog_spending("XXXINVALID", 2020L, "Corrections"),
    "not found|v0.1"
  )
  expect_s3_class(r, "tbl_df")
  expect_equal(nrow(r), 0L)
  expect_true("notes" %in% names(r))
  prov <- attr(r, "provenance")
  expect_false(is.null(prov))
  expect_equal(prov$scope$govids_missing, "XXXINVALID")
  expect_equal(length(prov$scope$govids_found), 0L)
})

test_that("cog_spending records found + missing govids in provenance", {
  skip_if_no_corpus()
  suppressMessages(
    r <- cog_spending(c("101006006", "XXXINVALID"), 2020L, "Corrections")
  )
  prov <- attr(r, "provenance")
  expect_equal(sort(prov$scope$govids_found), "101006006")
  expect_equal(sort(prov$scope$govids_missing), "XXXINVALID")
})

test_that("cog_spending result has provenance attribute matching schema", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2020L, "Corrections")
  prov <- attr(r, "provenance")
  expect_type(prov, "list")
  expect_equal(prov$verb, "cog_spending")
  required <- c("verb", "target", "years", "scope", "manifest", "sql_query")
  expect_true(all(required %in% names(prov)))
  expect_equal(prov$years, 2020L)
  expect_equal(prov$category, "Corrections")
  expect_type(prov$sql_query, "character")
  expect_true(grepl("spending_annotated", prov$sql_query))
  expect_type(prov$codes_summed$observed, "character")
  expect_true(all(c("E04") %in% prov$codes_summed$observed))
})

test_that("cog_spending rejects invalid inputs", {
  expect_error(cog_spending(list(), 2020L), "character|data frame")
  expect_error(cog_spending("101006006", "2020"), "years")
})

test_that("cog_spending accepts a cog_gov_search result directly", {
  skip_if_no_corpus()
  picks <- cog_gov_search("^BROWARD COUNTY$", state = "FL", type = "county")
  expect_gt(nrow(picks), 0L)
  r <- cog_spending(picks, 2020L, "Corrections")
  expect_equal(unique(r$canonical_govid), "101006006")
})

test_that("cog_spending accepts a cog_find_peers result directly", {
  skip_if_no_corpus()
  peers <- cog_find_peers("101006006", max_peers = 3L)
  r <- cog_spending(peers, 2020L, "Police")
  expect_setequal(unique(r$canonical_govid),
                  sort(peers$canonical_govid))
})

test_that("cog_spending rejects data.frame without canonical_govid column", {
  bad <- tibble::tibble(foo = "bar")
  expect_error(cog_spending(bad, 2020L), "canonical_govid")
})

test_that("cog_spending accepts a basket-mode cog_gov_search result", {
  skip_if_no_corpus()
  basket <- cog_gov_search(
    name  = c("BROWARD COUNTY", "SAN DIEGO COUNTY"),
    state = c("FL",             "CA")
  )
  expect_equal(nrow(basket), 2L)
  spending <- cog_spending(basket, years = 2019:2020, category = "Police")
  expect_s3_class(spending, "tbl_df")
  expect_setequal(unique(spending$canonical_govid), basket$canonical_govid)
})

test_that("per_capita denominator is the per-year F-33 population", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("101006006", years = 2019:2020,
                      category = "Police", per_capita = TRUE)
    r_ops <- r[r$spend_subtype == "operations", ]
    # Implied denominator from amt_nominal / amt_per_capita_nominal
    implied_pop <- r_ops$amt_nominal / r_ops$amt_per_capita_nominal
    names(implied_pop) <- r_ops$year
    # Use absolute tolerance: within 1 person of per-year F-33 values.
    # Hardcoded values are Broward County's per-year Census F-33 population
    # from the bundled fixture (regenerated 2026-04-29 against cog_pipeline
    # aad34c6 + bd3e744). 1,940,907 is the static ACS 2018-2022 5-year value
    # the legacy implementation would use; we assert it is NOT what we get.
    expect_true(abs(implied_pop[["2019"]] - 1935878) < 1)
    expect_true(abs(implied_pop[["2020"]] - 1952778) < 1)
    expect_false(all(abs(implied_pop - 1940907) < 1))
  })
})
