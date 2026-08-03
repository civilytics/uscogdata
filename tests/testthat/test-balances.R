test_that("balance views register and carry only balance codes", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())

  views <- DBI::dbGetQuery(con,
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'main' AND table_type = 'VIEW'"
  )$table_name
  expect_true(all(c("balance_long", "balance_annotated") %in% views))

  # Every item_code in balance_long is a category_type = 'balance' member.
  leak <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM balance_long
     WHERE item_code NOT IN (
       SELECT item_code FROM summary_categories WHERE category_type = 'balance')"
  )$n
  expect_identical(as.integer(leak), 0L)

  # And no aggregate row survives, mirroring revenue_long.
  agg <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM balance_long WHERE is_aggregate"
  )$n
  expect_identical(as.integer(agg), 0L)

  # balance_annotated exposes the subtype column the verb groups on.
  cols <- DBI::dbGetQuery(con,
    "SELECT column_name FROM information_schema.columns
     WHERE table_name = 'balance_annotated'"
  )$column_name
  expect_true(all(c("category", "category_type", "balance_subtype") %in% cols))
})

test_that("balance views are skipped on a corpus without balance_subtype", {
  skip_if_no_corpus()
  with_corpus_missing_balance_subtype({
    con <- cog_open()
    on.exit(cog_close())
    views <- DBI::dbGetQuery(con,
      "SELECT table_name FROM information_schema.tables
       WHERE table_schema = 'main' AND table_type = 'VIEW'"
    )$table_name
    # Registration must SKIP them, not error -- an older corpus stays usable.
    expect_false(any(c("balance_long", "balance_annotated") %in% views))
    expect_true("revenue_long" %in% views)
  })
})
