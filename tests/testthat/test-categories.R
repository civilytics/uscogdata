test_that("cog_categories returns all categories grouped by subtype", {
  skip_if_no_corpus()
  r <- cog_categories()
  expect_s3_class(r, "tbl_df")
  expected <- c("category", "category_type", "subtype",
                "n_codes", "item_codes")
  expect_true(all(expected %in% names(r)))
  expect_gt(nrow(r), 10L)
  # corpus preserves Census-native "expenditure" vocabulary; the API takes
  # "spending" as a friendlier alias.
  #
  # `balance` joined as a third category_type with the cash-and-security
  # holding codes (pipeline#76). `cog_categories()` is a CATALOGUE verb, not a
  # money verb, so it surfaces every category_type the corpus carries -- the
  # stock/flow guard belongs on cog_spending()/cog_revenue(), which must never
  # return a balance row.
  expect_setequal(unique(r$category_type),
                  c("expenditure", "revenue", "balance"))
})

test_that("cog_categories(type = 'spending') returns only expenditure rows", {
  skip_if_no_corpus()
  r <- cog_categories(type = "spending")
  expect_true(all(r$category_type == "expenditure"))
  # "assistance" (the J-prefix aid/benefit codes) joined the vocabulary with
  # the crosswalk completion in cog_pipeline#60/#65 -- every flow code
  # carrying dollars now maps to a category.
  # `interest` (I89, I91-I94) and `insurance_benefits` (Y05/Y06/Y14/Y53)
  # joined with the I/Q/Y flow batch -- the last two characters of Census's
  # expenditure taxonomy. `interest` is what makes the three-concept model
  # computable: primary = direct minus debt service.
  # Exclude pseudo-category which has NA for subtype
  r_crosswalk <- r[r$category != "All Categories", ]
  expect_true(all(r_crosswalk$subtype %in%
                  c("operations", "capital", "intergovernmental", "assistance",
                    "interest", "insurance_benefits")))
})

test_that("cog_categories surfaces the intergovernmental spending subtype", {
  skip_if_no_corpus()
  r <- cog_categories(type = "spending")
  expect_true("intergovernmental" %in% r$subtype)
  # IG rows reuse the existing functional categories -- they add a subtype,
  # not new category values.
  ig_cats     <- sort(unique(r$category[r$subtype == "intergovernmental"]))
  direct_cats <- sort(unique(r$category[r$subtype != "intergovernmental"]))
  expect_true(all(ig_cats %in% c(direct_cats, "Other Education")))
})

test_that("cog_categories(type = 'revenue') returns only revenue rows", {
  skip_if_no_corpus()
  r <- cog_categories(type = "revenue")
  expect_true(all(r$category_type == "revenue"))
  # The four non-general subtypes are deliberately NOT own_source: Census's
  # General Revenue excludes insurance trust (Y01 alone is $1.31T corpus-wide,
  # plus the employee-retirement X codes), utility (A91-A94) and liquor store
  # (A90) revenue by definition, which is what makes both of its published
  # revenue concepts computable -- see `revenue_concept` in `?cog_revenue`.
  # Exclude pseudo-category which has NA for subtype
  r_crosswalk <- r[r$category != "All Categories", ]
  expect_true(all(r_crosswalk$subtype %in%
                  c("own_source", "federal", "state", "local_aid",
                    "insurance_trust", "utility", "liquor_store")))
})

test_that("cog_categories(pattern = ...) filters case-insensitively", {
  skip_if_no_corpus()
  r <- cog_categories(pattern = "police")
  expect_gt(nrow(r), 0L)
  expect_true(all(grepl("Police", r$category, ignore.case = TRUE)))
})

test_that("cog_categories has one row per (category, subtype)", {
  skip_if_no_corpus()
  r <- cog_categories()
  # Exclude pseudo-category which is not a crosswalk entry
  r <- r[r$category != "All Categories", ]
  key <- paste(r$category, r$subtype, sep = "|")
  expect_equal(length(key), length(unique(key)))
})

test_that("cog_categories item_codes is non-empty comma-separated string", {
  skip_if_no_corpus()
  r <- cog_categories()
  # Exclude pseudo-category which has NA for n_codes and item_codes
  r <- r[r$category != "All Categories", ]
  expect_true(all(nzchar(r$item_codes)))
  expect_true(all(r$n_codes >= 1L))
  # n_codes should equal count of commas + 1
  expect_equal(r$n_codes,
               vapply(strsplit(r$item_codes, ","), length, integer(1)))
})

test_that("cog_categories sorted by category_type, category, subtype", {
  skip_if_no_corpus()
  r <- cog_categories()
  sorted <- r[order(r$category_type, r$category, r$subtype), ]
  expect_identical(r, sorted)
})

test_that("cog_categories rejects invalid type", {
  expect_error(cog_categories(type = "both"), "type")
})

test_that("cog_categories() surfaces balance subtypes", {
  skip_if_no_corpus()
  with_fixture_corpus({
    cc <- cog_categories()
    b <- cc[cc$category_type == "balance", ]
    expect_true(nrow(b) > 0L)

    # Every balance row must carry its subtype. Before the COALESCE included
    # balance_subtype these were all NA, which silently made the balance
    # taxonomy undiscoverable -- cog-api derives its subtype vocabulary from
    # this function, so an NA here becomes an unusable API parameter.
    expect_false(any(is.na(b$subtype)))

    # The exact set, read independently from the crosswalk rather than from
    # the function under test.
    con2 <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con2, shutdown = TRUE), add = TRUE)
    p <- file.path(fixture_corpus_path(), "data", "summary_categories.parquet")
    want <- DBI::dbGetQuery(con2, sprintf(
      "SELECT DISTINCT balance_subtype FROM read_parquet(%s)
       WHERE category_type = 'balance' AND balance_subtype IS NOT NULL
       ORDER BY 1", uscogdata:::.sql_lit_chr(p)))$balance_subtype
    expect_true(length(want) > 1L)
    expect_identical(sort(unique(b$subtype)), sort(want))
  })
})

test_that('cog_categories(type = "balance") filters to holdings', {
  skip_if_no_corpus()
  with_fixture_corpus({
    b <- cog_categories(type = "balance")
    expect_true(nrow(b) > 0L)
    expect_identical(unique(b$category_type), "balance")
    expect_false(any(is.na(b$subtype)))
  })
})
