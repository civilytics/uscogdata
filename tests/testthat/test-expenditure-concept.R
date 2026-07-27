test_that("the corpus contains no K-prefix rows, so the Direct leg omits K", {
  con <- .ensure_session()
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM long WHERE LEFT(item_code, 1) = 'K'")$n
  expect_equal(n, 0)

  sql_files <- c("20-spending_long.sql", "22-spending_long_harmonized.sql")
  for (f in sql_files) {
    txt <- paste(readLines(system.file("sql", f, package = "uscogdata")),
                 collapse = " ")
    expect_false(grepl("'K'", txt, fixed = TRUE),
                 label = paste(f, "must not reference the inert K prefix"))
  }
})
