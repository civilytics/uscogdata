# Baseline at branch point: 843 PASS / 0 FAIL / 0 SKIP / 0 WARN (2026-08-05, origin/main 2fc9e75)

test_that(".build_verb_sql emits a literal category and no category filter in all-categories mode", {
  sql <- uscogdata:::.build_verb_sql(
    view         = "spending_annotated",
    subtype_col  = "spend_subtype",
    govid        = "552025209777",
    years        = 2019L,
    category     = NULL,
    subtype_scope = c("operations", "capital"),
    all_categories = TRUE
  )

  expect_match(sql, "'All Categories' AS category", fixed = TRUE)
  # no category filter of any kind
  expect_false(grepl("AND category IN", sql, fixed = TRUE))
  # category is not a grouping key
  expect_false(grepl("GROUP BY year, canonical_govid, gov_name, xwalk_gov_name, spend_subtype, category",
                     sql, fixed = TRUE))
  # the subtype allowlist still applies -- this is what makes the sum a concept
  expect_match(sql, "AND spend_subtype IN ('operations','capital')", fixed = TRUE)
})

test_that(".build_verb_sql is unchanged when all_categories is FALSE", {
  args <- list(
    view = "spending_annotated", subtype_col = "spend_subtype",
    govid = "552025209777", years = 2019L, category = NULL,
    subtype_scope = c("operations", "capital")
  )
  old <- do.call(uscogdata:::.build_verb_sql, args)
  new <- do.call(uscogdata:::.build_verb_sql, c(args, list(all_categories = FALSE)))
  expect_identical(old, new)
  expect_match(new, "GROUP BY year, canonical_govid, gov_name, xwalk_gov_name, spend_subtype, category",
               fixed = TRUE)
})

test_that(".ALL_CATEGORIES is the exact reserved string", {
  expect_identical(uscogdata:::.ALL_CATEGORIES, "All Categories")
})

test_that('cog_spending(category = "All Categories") sums to the per-category total', {
  gov <- "552025209777"
  by_cat <- cog_spending(gov, 2019L)
  total  <- cog_spending(gov, 2019L, category = "All Categories")

  expect_true(nrow(total) > 0L)
  expect_setequal(unique(total$category), "All Categories")
  # one row per subtype present in the by-category result
  expect_setequal(unique(total$spend_subtype), unique(by_cat$spend_subtype))
  expect_equal(nrow(total), length(unique(by_cat$spend_subtype)))

  # the dollars agree, per subtype
  lhs <- tapply(by_cat$amt_nominal, by_cat$spend_subtype, sum)
  rhs <- tapply(total$amt_nominal,  total$spend_subtype,  sum)
  expect_equal(as.numeric(rhs[names(lhs)]), as.numeric(lhs), tolerance = 1e-8)
})

test_that('"All Categories" respects expenditure_concept', {
  gov <- "552025209777"
  prim <- cog_spending(gov, 2019L, category = "All Categories",
                       expenditure_concept = "primary")
  dir  <- cog_spending(gov, 2019L, category = "All Categories",
                       expenditure_concept = "direct")
  # direct = primary plus interest and insurance benefits, so it is never smaller
  expect_gte(sum(dir$amt_nominal), sum(prim$amt_nominal))
})

test_that('"All Categories" works on revenue and respects revenue_concept', {
  gov <- "552025209777"
  gen <- cog_revenue(gov, 2019L, category = "All Categories",
                     revenue_concept = "general")
  tot <- cog_revenue(gov, 2019L, category = "All Categories",
                     revenue_concept = "total")
  expect_setequal(unique(gen$category), "All Categories")
  expect_gte(sum(tot$amt_nominal), sum(gen$amt_nominal))
})

test_that('"All Categories" cannot be combined with another category', {
  expect_error(
    cog_spending("552025209777", 2019L, category = c("All Categories", "Police")),
    class = "uscogdata_all_categories_not_combinable"
  )
})

test_that('"All Categories" is recorded in provenance', {
  r <- cog_spending("552025209777", 2019L, category = "All Categories")
  expect_identical(cog_explain(r, format = "list")$category, "All Categories")
})

test_that('"All Categories" combines with subtype to give operating totals', {
  gov <- "552025209777"
  ops_by_cat <- cog_spending(gov, 2019L)
  ops_by_cat <- ops_by_cat[ops_by_cat$spend_subtype == "operations", ]
  ops_total  <- cog_spending(gov, 2019L, category = "All Categories")
  ops_total  <- ops_total[ops_total$spend_subtype == "operations", ]
  expect_equal(sum(ops_total$amt_nominal), sum(ops_by_cat$amt_nominal),
               tolerance = 1e-8)
})
