test_that("cog_revenue returns expected shape for Broward Property Tax 2020", {
  skip_if_no_corpus()
  r <- cog_revenue("101006006", years = 2020L, category = "Property Tax")
  expect_s3_class(r, "tbl_df")
  expected_cols <- c("year", "canonical_govid", "gov_name", "revenue_subtype",
                     "category", "amt_nominal", "codes_included",
                     "aggregate_fallback", "notes")
  expect_true(all(expected_cols %in% names(r)))
  expect_equal(unique(r$canonical_govid), "101006006")
  expect_equal(unique(r$year), 2020L)
})

test_that("cog_revenue with no category filter returns multiple categories", {
  skip_if_no_corpus()
  r <- cog_revenue("101006006", years = 2020L)
  expect_gt(length(unique(r$category)), 1L)
})

test_that("cog_revenue with per_capita + adjust_to_year adds all columns", {
  skip_if_no_corpus()
  r <- cog_revenue("101006006", 2020L,
                   per_capita = TRUE, adjust_to_year = 2022L)
  expect_true(all(c("amt_nominal", "amt_real",
                    "amt_per_capita_nominal", "amt_per_capita_real") %in%
                  names(r)))
})

test_that("cog_revenue result has provenance attribute", {
  skip_if_no_corpus()
  r <- cog_revenue("101006006", 2020L)
  prov <- attr(r, "provenance")
  expect_equal(prov$verb, "cog_revenue")
  expect_true(grepl("revenue_annotated", prov$sql_query))
})

test_that("cog_revenue rejects invalid inputs", {
  expect_error(cog_revenue(list(), 2020L), "character|data frame")
})
