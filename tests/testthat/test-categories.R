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
  expect_true(all(r$subtype %in%
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
  # `insurance_trust` (Y01/Y02/Y04/Y11/Y12/Y51/Y52) is deliberately NOT
  # own_source: Census's "General Revenue" excludes insurance trust revenue,
  # and Y01 alone is $1.31T corpus-wide.
  expect_true(all(r$subtype %in%
                  c("own_source", "federal", "state", "local_aid",
                    "insurance_trust")))
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
  key <- paste(r$category, r$subtype, sep = "|")
  expect_equal(length(key), length(unique(key)))
})

test_that("cog_categories item_codes is non-empty comma-separated string", {
  skip_if_no_corpus()
  r <- cog_categories()
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
