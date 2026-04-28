test_that("cog_gov_search by name pattern returns matches", {
  skip_if_no_corpus()
  r <- cog_gov_search("^BROWARD")
  expect_s3_class(r, "tbl_df")
  expect_true(all(grepl("^BROWARD", r$gov_name)))
  expect_true("canonical_govid" %in% names(r))
})

test_that("cog_gov_search case-insensitive", {
  skip_if_no_corpus()
  r <- cog_gov_search("broward")
  expect_gt(nrow(r), 0L)
})

test_that("cog_gov_search by state abbreviation", {
  skip_if_no_corpus()
  r <- cog_gov_search(state = "FL", type = 1L)
  expect_true(all(r$fips_state == "12"))
  expect_true(all(r$govs_type == 1L))
})

test_that("cog_gov_search accepts FIPS int for state", {
  skip_if_no_corpus()
  r <- cog_gov_search(state = 12, type = "county")
  expect_true(all(r$fips_state == "12"))
  expect_true(all(r$govs_type == 1L))
})

test_that("cog_gov_search accepts type as name string", {
  skip_if_no_corpus()
  for (pair in list(c("state", 0), c("county", 1), c("city", 2), c("township", 3))) {
    r <- cog_gov_search(type = pair[1])
    expect_true(all(r$govs_type == as.integer(pair[2])))
  }
})

test_that("cog_gov_search for excluded types emits message and returns empty", {
  skip_if_no_corpus()
  expect_message(
    r <- cog_gov_search(type = 4L),
    "v0.1|excluded"
  )
  expect_equal(nrow(r), 0L)
  expect_true("canonical_govid" %in% names(r))
  expect_message(
    r2 <- cog_gov_search(type = "special_district"),
    "v0.1|excluded"
  )
  expect_equal(nrow(r2), 0L)
})

test_that("cog_gov_search combining filters", {
  skip_if_no_corpus()
  r <- cog_gov_search("BROWARD", state = "FL")
  expect_true(all(grepl("BROWARD", r$gov_name)))
  expect_true(all(r$fips_state == "12"))
})

test_that("cog_gov_search sorts by population desc", {
  skip_if_no_corpus()
  r <- cog_gov_search(state = "FL", type = 2L)
  nonNA <- r$population_acs[!is.na(r$population_acs)]
  expect_true(all(diff(nonNA) <= 0))
})

test_that("cog_gov_search rejects unknown type string", {
  expect_error(cog_gov_search(type = "galaxy"), "Unknown type")
})

test_that("cog_gov_search with no filters returns full registry", {
  skip_if_no_corpus()
  r <- cog_gov_search()
  expect_gt(nrow(r), 1000L)
})

# ---- basket mode internal helpers ----

test_that(".validate_basket_args recycles state from length 1", {
  out <- uscogdata:::.validate_basket_args(
    name  = c("Broward", "San Diego", "Austin"),
    state = "FL",
    type  = NULL
  )
  expect_equal(out$name,  c("Broward", "San Diego", "Austin"))
  expect_equal(out$state, c("FL", "FL", "FL"))
  expect_equal(out$type,  c(NA_character_, NA_character_, NA_character_))
})

test_that(".validate_basket_args recycles type from length 1", {
  out <- uscogdata:::.validate_basket_args(
    name  = c("San Diego", "Oakland"),
    state = "CA",
    type  = "city"
  )
  expect_equal(out$type, c("city", "city"))
})

test_that(".validate_basket_args accepts per-row state and type", {
  out <- uscogdata:::.validate_basket_args(
    name  = c("Broward", "San Diego"),
    state = c("FL", "CA"),
    type  = c(NA, "city")
  )
  expect_equal(out$state, c("FL", "CA"))
  expect_equal(out$type,  c(NA_character_, "city"))
})

test_that(".validate_basket_args rejects length-mismatched state", {
  expect_error(
    uscogdata:::.validate_basket_args(
      name  = c("Broward", "San Diego", "Austin"),
      state = c("FL", "CA"),
      type  = NULL
    ),
    regexp = "must be length 1 or 3"
  )
})

test_that(".validate_basket_args rejects length-mismatched type", {
  expect_error(
    uscogdata:::.validate_basket_args(
      name  = c("Broward", "San Diego"),
      state = "FL",
      type  = c("county", "city", "city")
    ),
    regexp = "must be length 1 or 2"
  )
})

test_that(".validate_basket_args allows NULL state and type", {
  out <- uscogdata:::.validate_basket_args(
    name  = c("Broward", "San Diego"),
    state = NULL,
    type  = NULL
  )
  expect_equal(out$state, c(NA_character_, NA_character_))
  expect_equal(out$type,  c(NA_character_, NA_character_))
})

test_that(".resolve_basket_row exact match returns one row", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "BROWARD COUNTY", state = "FL", type = NA_character_, con = con
  )
  expect_equal(out$status, "resolved")
  expect_equal(out$match_method, "exact")
  expect_equal(out$n_candidates, 1L)
  expect_equal(nrow(out$row), 1L)
  expect_equal(out$row$canonical_govid, "101006006")
  expect_equal(out$row$gov_name, "BROWARD COUNTY")
})

test_that(".resolve_basket_row exact match is case-insensitive", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "broward county", state = "FL", type = NA_character_, con = con
  )
  expect_equal(out$status, "resolved")
  expect_equal(out$match_method, "exact")
  expect_equal(out$row$canonical_govid, "101006006")
})

test_that(".resolve_basket_row exact match honors per-row type", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "SAN DIEGO CITY", state = "CA", type = "city", con = con
  )
  expect_equal(out$status, "resolved")
  expect_equal(out$row$canonical_govid, "052037010")
})
