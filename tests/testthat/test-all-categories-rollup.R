test_that('cog_geographic_rollup() accepts "All Categories" and agrees with per-category sums', {
  skip_if_no_corpus()
  govs <- cog_gov_search(name = NULL, state = "WI", type = 2L)
  expect_gt(nrow(govs), 1L)
  ids <- list(city = utils::head(govs$canonical_govid, 25L))

  by_cat <- cog_geographic_rollup(ids, category = NULL, years = 2019L)
  total  <- cog_geographic_rollup(ids, category = "All Categories", years = 2019L)

  expect_setequal(unique(total$category), "All Categories")
  # one row per (govid, subtype) that appears in the per-category result
  key_by_cat <- unique(paste(by_cat$canonical_govid, by_cat$spend_subtype))
  key_total  <- paste(total$canonical_govid, total$spend_subtype)
  expect_setequal(key_total, key_by_cat)

  lhs <- tapply(by_cat$amt_nominal, paste(by_cat$canonical_govid, by_cat$spend_subtype), sum)
  rhs <- tapply(total$amt_nominal,  key_total, sum)
  expect_equal(as.numeric(rhs[names(lhs)]), as.numeric(lhs), tolerance = 1e-8)
})

test_that('"All Categories" survives per_capita and inflation adjustment through the rollup', {
  skip_if_no_corpus()
  govs <- cog_gov_search(name = NULL, state = "WI", type = 2L)
  ids  <- list(city = utils::head(govs$canonical_govid, 10L))
  r <- cog_geographic_rollup(ids, category = "All Categories", years = 2019L,
                             per_capita = TRUE, adjust_to_year = 2020L)
  expect_true(all(c("amt_per_capita_nominal", "amt_real", "amt_per_capita_real") %in% names(r)))
  expect_setequal(unique(r$category), "All Categories")
  expect_true(all(is.finite(r$amt_real)))
})

test_that('cog_geographic_rollup() still refuses expenditure_concept = "total" with "All Categories"', {
  skip_if_no_corpus()
  govs <- cog_gov_search(name = NULL, state = "WI", type = 2L)
  ids  <- list(city = utils::head(govs$canonical_govid, 5L))
  expect_error(
    cog_geographic_rollup(ids, category = "All Categories", years = 2019L,
                          expenditure_concept = "total")
  )
})
