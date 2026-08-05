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
