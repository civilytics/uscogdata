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

test_that("expenditure_concept defaults to direct and preserves today's numbers", {
  gov <- "010000226085"                      # Alabama state government
  base <- cog_spending(gov, years = 2019, category = "Police")
  expl <- cog_spending(gov, years = 2019, category = "Police",
                       expenditure_concept = "direct")
  expect_equal(base$amt_nominal, expl$amt_nominal)
  expect_false("intergovernmental" %in% base$spend_subtype)
})

test_that("expenditure_concept = 'total' adds an intergovernmental subtype", {
  gov <- "010000226085"
  d <- cog_spending(gov, years = 2019, category = "Police",
                    expenditure_concept = "direct")
  t <- cog_spending(gov, years = 2019, category = "Police",
                    expenditure_concept = "total")
  expect_true("intergovernmental" %in% t$spend_subtype)
  # Direct rows are untouched; Total only ever ADDS.
  dt <- t[t$spend_subtype != "intergovernmental", ]
  expect_equal(sort(dt$amt_nominal), sort(d$amt_nominal))
  expect_gt(sum(t$amt_nominal), sum(d$amt_nominal))
})

test_that("legacy-era Total does not collapse to Direct (the is_aggregate trap)", {
  # In the wide era the IG dollars live almost entirely on aggregate-flagged
  # rows. A Total leg that inherited the Direct leg's NOT is_aggregate filter
  # would silently return Total == Direct here.
  gov <- "010000226085"
  d <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "direct")
  t <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total")
  expect_true("intergovernmental" %in% t$spend_subtype)
  ig <- sum(t$amt_nominal[t$spend_subtype == "intergovernmental"])
  expect_gt(ig, 0)
  expect_gt(sum(t$amt_nominal), sum(d$amt_nominal))
})

test_that("the IG leg never includes the L-- family total", {
  con <- .ensure_session()
  codes <- DBI::dbGetQuery(con,
    "SELECT DISTINCT item_code FROM ig_long")$item_code
  expect_false(any(grepl("--$", codes)))
  expect_true(all(substr(codes, 1, 1) %in% c("M", "L")))
})

test_that("expenditure_concept rejects unknown values", {
  expect_error(
    cog_spending("010000226085", years = 2019, expenditure_concept = "gross"),
    class = "rlang_error"
  )
})

test_that("total composes with basis = 'raw' and basis = 'harmonized'", {
  gov <- "010000226085"
  h <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total", basis = "harmonized")
  r <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total", basis = "raw")
  ig_h <- sum(h$amt_nominal[h$spend_subtype == "intergovernmental"])
  ig_r <- sum(r$amt_nominal[r$spend_subtype == "intergovernmental"])
  # The only IG harmonization rule is M38 -> M36 (year-disjoint), so the IG
  # total must agree between bases even though the code labels may differ.
  expect_equal(ig_h, ig_r)
})

test_that("recipe = and expenditure_concept = 'total' together aborts", {
  expect_error(
    cog_spending("121011212191", 2020L, recipe = "corrections_combined",
                expenditure_concept = "total"),
    class = "uscogdata_recipe_concept_conflict"
  )
})
