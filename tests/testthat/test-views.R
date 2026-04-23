test_that("all expected views register on session open", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  views <- DBI::dbGetQuery(con,
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'main' AND table_type = 'VIEW'"
  )
  expected <- c(
    "long", "spending_long", "revenue_long",
    "canonical_fips_xwalk", "summary_categories",
    "spending_annotated", "revenue_annotated"
  )
  expect_true(all(expected %in% views$table_name))
})

test_that("spending_long filters to E/F/G/K prefixes and excludes aggregates", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  prefixes <- DBI::dbGetQuery(con,
    "SELECT DISTINCT LEFT(item_code, 1) AS pfx FROM spending_long"
  )$pfx
  expect_true(all(prefixes %in% c("E", "F", "G", "K")))

  agg_count <- DBI::dbGetQuery(con,
    "SELECT count(*) AS n FROM spending_long WHERE is_aggregate"
  )$n
  expect_equal(agg_count, 0)
})

test_that("revenue_long filters to T/A/U/B/C/D prefixes and excludes aggregates", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  prefixes <- DBI::dbGetQuery(con,
    "SELECT DISTINCT LEFT(item_code, 1) AS pfx FROM revenue_long"
  )$pfx
  expect_true(all(prefixes %in% c("T", "A", "U", "B", "C", "D")))

  agg_count <- DBI::dbGetQuery(con,
    "SELECT count(*) AS n FROM revenue_long WHERE is_aggregate"
  )$n
  expect_equal(agg_count, 0)
})

test_that("spending_annotated carries category + xwalk columns", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  row <- DBI::dbGetQuery(con,
    "SELECT * FROM spending_annotated LIMIT 1"
  )
  for (nm in c("canonical_govid", "item_code", "amt",
               "xwalk_gov_name", "govs_type", "population_acs",
               "category", "spend_subtype")) {
    expect_true(nm %in% names(row), info = paste("missing column:", nm))
  }
})
