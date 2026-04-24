test_that("cog_explain prints verb header and target", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2020L, "Corrections")
  # cli writes to stderr; capture both stdout and message streams.
  txt <- paste(c(
    capture.output(cog_explain(r)),
    capture.output(cog_explain(r), type = "message")
  ), collapse = "\n")
  expect_true(grepl("cog_spending", txt))
  expect_true(grepl("Corrections", txt))
  expect_true(grepl("101006006", txt))
})

test_that("cog_explain format='list' returns structured provenance", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2020L, "Corrections")
  prov <- cog_explain(r, format = "list")
  expect_identical(prov, attr(r, "provenance"))
})

test_that("cog_explain returns result invisibly for chaining", {
  skip_if_no_corpus()
  r <- cog_spending("101006006", 2020L, "Corrections")
  res <- withVisible(cog_explain(r))
  expect_false(res$visible)
  expect_identical(res$value, r)
})

test_that("cog_explain errors on non-verb input", {
  df <- tibble::tibble(a = 1)
  expect_error(cog_explain(df), "provenance")
})
