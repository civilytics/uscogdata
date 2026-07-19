test_that("cog_explain prints verb header and target", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections")
  # cli writes to stderr; capture both stdout and message streams.
  txt <- paste(c(
    capture.output(cog_explain(r)),
    capture.output(cog_explain(r), type = "message")
  ), collapse = "\n")
  expect_true(grepl("cog_spending", txt))
  expect_true(grepl("Corrections", txt))
  expect_true(grepl("121011212191", txt))
})

test_that("cog_explain format='list' returns structured provenance", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections")
  prov <- cog_explain(r, format = "list")
  expect_identical(prov, attr(r, "provenance"))
})

test_that("cog_explain returns result invisibly for chaining", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections")
  res <- withVisible(cog_explain(r))
  expect_false(res$visible)
  expect_identical(res$value, r)
})

test_that("cog_explain errors on non-verb input", {
  df <- tibble::tibble(a = 1)
  expect_error(cog_explain(df), "provenance")
})

test_that("cog_explain prints basis + harmonization block", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections")
  txt <- paste(c(
    capture.output(cog_explain(r)),
    capture.output(cog_explain(r), type = "message")
  ), collapse = "\n")
  expect_true(grepl("Basis: harmonized", txt))
  expect_true(grepl("Harmonization", txt))
  expect_true(grepl("Excluded 0 row", txt))
})

test_that("cog_explain prints a Recipe section for recipe = results", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", c(2011L, 2012L), recipe = "corrections_combined")
  txt <- paste(c(
    capture.output(cog_explain(r)),
    capture.output(cog_explain(r), type = "message")
  ), collapse = "\n")
  expect_true(grepl("Recipe", txt))
  expect_true(grepl("corrections_combined", txt))
  expect_true(grepl("E04", txt))
  expect_true(grepl("E05", txt))
})

test_that("cog_explain prints a Suggestions section when the provenance has one", {
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("121011212191", c(2011L, 2012L), category = "Corrections")
  )
  txt <- paste(c(
    capture.output(cog_explain(r)),
    capture.output(cog_explain(r), type = "message")
  ), collapse = "\n")
  expect_true(grepl("Suggestions", txt))
  expect_true(grepl("corrections_combined", txt))
  expect_true(grepl("re-run with recipe", txt))
})

test_that("cog_explain prints denominator + popyear_range + counts", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", years = 2019:2020,
                      category = "Police", per_capita = TRUE)
    out <- paste(c(
      capture.output(cog_explain(r)),
      capture.output(cog_explain(r), type = "message")
    ), collapse = "\n")
    expect_true(grepl("Census F-33", out))
    expect_true(grepl("popyear", out, ignore.case = TRUE))
    expect_true(grepl("census_f33", out))
    # popyear_range should render as 4-digit calendar years, not raw 2-digit
    expect_true(grepl("2019-2020", out))
    expect_false(grepl("popyear range: 19-20", out, fixed = TRUE))
  })
})
