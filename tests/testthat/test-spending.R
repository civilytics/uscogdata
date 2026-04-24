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
  r <- cog_spending("101006006", 2015:2020, "Corrections",
                    adjust_to_year = 2022L)
  expect_true("amt_real" %in% names(r))
  r2015 <- dplyr::filter(r, year == 2015L)
  expect_true(any(r2015$amt_nominal != r2015$amt_real))
})

test_that("cog_spending with per_capita + adjust_to_year adds all columns", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2020L, "Corrections",
                    per_capita = TRUE, adjust_to_year = 2022L)
  expect_true(all(c("amt_nominal", "amt_real",
                    "amt_per_capita_nominal", "amt_per_capita_real") %in%
                  names(r)))
})

test_that("cog_spending for unknown govid returns empty tibble", {
  skip_if_no_corpus()
  r <- cog_spending("XXXINVALID", 2020L, "Corrections")
  expect_s3_class(r, "tbl_df")
  expect_equal(nrow(r), 0L)
  expect_true("notes" %in% names(r))
  # provenance still attached
  expect_false(is.null(attr(r, "provenance")))
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
  expect_error(cog_spending(123, 2020L), "character")
  expect_error(cog_spending("101006006", "2020"), "years")
})
