# Mirror of test-spending-pagination.R for cog_revenue(), which shares the
# same .verb_spendrev()/.build_verb_sql() pushdown -- see that file for the
# incident this fixes.

test_that("cog_revenue limit/offset page correctly and report total_rows", {
  skip_if_no_corpus()
  full <- cog_revenue("121011212191", years = 2019:2020, category = NULL)
  page <- cog_revenue("121011212191", years = 2019:2020, category = NULL,
                      limit = 5L, offset = 3L)
  expect_equal(nrow(page), 5L)
  expect_equal(page[c("year", "canonical_govid", "revenue_subtype", "category")],
              full[4:8, c("year", "canonical_govid", "revenue_subtype", "category")],
              ignore_attr = TRUE)
  expect_equal(attr(page, "total_rows"), nrow(full))
})

test_that("cog_revenue limit unset by default leaves total_rows absent", {
  skip_if_no_corpus()
  r <- cog_revenue("121011212191", 2020L, "Property Tax")
  expect_null(attr(r, "total_rows"))
})

test_that("cog_revenue complete + limit conflict aborts the same way as cog_spending", {
  skip_if_no_corpus()
  expect_error(
    cog_revenue("121011212191", 2020L, "Property Tax", complete = TRUE, limit = 5L),
    class = "uscogdata_complete_pagination_conflict"
  )
})
