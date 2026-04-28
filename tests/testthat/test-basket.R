test_that("cog_basket_resolution returns the sidecar tibble", {
  basket <- suppressMessages(cog_gov_search(
    name  = c("Broward", "Notarealplace"),
    state = c("FL",      "NY")
  ))
  res <- cog_basket_resolution(basket)
  expect_s3_class(res, "tbl_df")
  expect_equal(nrow(res), 2L)
  expect_setequal(colnames(res), c(
    "query_name", "query_state", "query_type", "status",
    "match_method", "canonical_govid", "gov_name", "n_candidates"
  ))
})

test_that("cog_basket_resolution(expand_candidates = TRUE) keeps candidates list-col", {
  basket <- suppressMessages(cog_gov_search(
    name  = c("Broward", "Notarealplace"),
    state = c("FL",      "NY")
  ))
  res <- cog_basket_resolution(basket, expand_candidates = TRUE)
  expect_true("candidates" %in% colnames(res))
  expect_true(is.list(res$candidates))
})

test_that("cog_basket_resolution errors on a non-basket tibble", {
  utility <- cog_gov_search("BROWARD")
  expect_error(
    cog_basket_resolution(utility),
    regexp = "no resolution attribute"
  )
})

test_that("cog_basket_unresolved filters to ambiguous and no_match", {
  basket <- suppressMessages(cog_gov_search(
    name  = c("Broward", "San Diego", "Notarealplace"),
    state = c("FL",      "CA",        "NY")
  ))
  unres <- cog_basket_unresolved(basket)
  expect_equal(nrow(unres), 2L)
  expect_setequal(unres$status, c("ambiguous", "no_match"))
  expect_true("candidates" %in% colnames(unres))
})

test_that("cog_basket_unresolved returns 0 rows when basket is clean", {
  basket <- cog_gov_search(
    name  = c("BROWARD COUNTY", "SAN DIEGO CITY"),
    state = c("FL",             "CA")
  )
  unres <- cog_basket_unresolved(basket)
  expect_equal(nrow(unres), 0L)
})
