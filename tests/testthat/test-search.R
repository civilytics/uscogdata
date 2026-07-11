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
  expect_equal(out$row$canonical_govid, "121011212191")
  expect_equal(out$row$gov_name, "BROWARD COUNTY")
})

test_that(".resolve_basket_row exact match is case-insensitive", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "broward county", state = "FL", type = NA_character_, con = con
  )
  expect_equal(out$status, "resolved")
  expect_equal(out$match_method, "exact")
  expect_equal(out$row$canonical_govid, "121011212191")
})

test_that(".resolve_basket_row exact match honors per-row type", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "SAN DIEGO CITY", state = "CA", type = "city", con = con
  )
  expect_equal(out$status, "resolved")
  expect_equal(out$row$canonical_govid, "062073207598")
})

test_that(".resolve_basket_row substring fallback resolves single match", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "Broward", state = "FL", type = NA_character_, con = con
  )
  expect_equal(out$status, "resolved")
  expect_equal(out$match_method, "substring")
  expect_equal(out$n_candidates, 1L)
  expect_equal(out$row$canonical_govid, "121011212191")
})

test_that(".resolve_basket_row no_match returns 0-row tibble", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "Notarealplace", state = "NY", type = NA_character_, con = con
  )
  expect_equal(out$status, "no_match")
  expect_true(is.na(out$match_method))
  expect_equal(out$n_candidates, 0L)
  expect_equal(nrow(out$row), 0L)
  expect_equal(nrow(out$candidates), 0L)
})

test_that(".resolve_basket_row treats empty/whitespace name as no_match", {
  con <- uscogdata:::.ensure_session()
  out_empty <- uscogdata:::.resolve_basket_row(
    name = "", state = "FL", type = NA_character_, con = con
  )
  expect_equal(out_empty$status, "no_match")

  out_ws <- uscogdata:::.resolve_basket_row(
    name = "   ", state = "FL", type = NA_character_, con = con
  )
  expect_equal(out_ws$status, "no_match")
})

test_that(".resolve_basket_row largest_pop within single type", {
  # FL Miami substring matches 10 cities (all govs_type = 2), largest pop
  # is MIAMI CITY at 443665. Under Phase P canonical naming, MIAMI-DADE
  # COUNTY (govs_type = 1) also contains "Miami", so `type = "city"` pins
  # the match set to a single type (as the query docs promise it will for
  # per-row `type`), keeping this test's original intent: multiple
  # same-type name matches resolve to the largest-population row.
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "Miami", state = "FL", type = "city", con = con
  )
  expect_equal(out$status, "largest_pop")
  expect_equal(out$match_method, "substring")
  expect_gte(out$n_candidates, 2L)
  expect_equal(out$row$canonical_govid, "122086194757")
  expect_equal(out$row$gov_name, "MIAMI CITY")
})

test_that(".resolve_basket_row ambiguous across types", {
  # SAN DIEGO substring matches both SAN DIEGO COUNTY (type 1) and
  # SAN DIEGO CITY (type 2) in CA.
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "San Diego", state = "CA", type = NA_character_, con = con
  )
  expect_equal(out$status, "ambiguous")
  expect_true(is.na(out$match_method))
  expect_equal(out$n_candidates, 2L)
  expect_equal(nrow(out$row), 0L)
  expect_equal(nrow(out$candidates), 2L)
  expect_setequal(out$candidates$govs_type, c(1L, 2L))
})

test_that(".resolve_basket_row resolves with type override on ambiguous case", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "San Diego", state = "CA", type = "city", con = con
  )
  expect_equal(out$status, "resolved")
  expect_equal(out$match_method, "substring")
  expect_equal(out$row$canonical_govid, "062073207598")
})

# ---- basket mode public surface ----

test_that("cog_gov_search basket mode resolves clean inputs in input order", {
  skip_if_no_corpus()
  basket <- cog_gov_search(
    name  = c("BROWARD COUNTY", "SAN DIEGO CITY", "AUSTIN CITY"),
    state = c("FL",             "CA",             "TX")
  )
  expect_s3_class(basket, "tbl_df")
  expect_equal(nrow(basket), 3L)
  expect_equal(basket$canonical_govid, c("121011212191", "062073207598", "482453176394"))
  expect_equal(basket$gov_name, c("BROWARD COUNTY", "SAN DIEGO CITY", "AUSTIN CITY"))
})

test_that("cog_gov_search basket mode attaches a resolution sidecar", {
  skip_if_no_corpus()
  basket <- cog_gov_search(
    name  = c("Broward", "San Diego"),
    state = c("FL",      "CA"),
    type  = c(NA,        "city")
  )
  res <- attr(basket, "resolution")
  expect_s3_class(res, "tbl_df")
  expect_equal(nrow(res), 2L)
  expect_equal(res$query_name, c("Broward", "San Diego"))
  expect_equal(res$query_state, c("FL", "CA"))
  expect_equal(res$query_type, c(NA_character_, "city"))
  expect_equal(res$status, c("resolved", "resolved"))
  expect_equal(res$match_method, c("substring", "substring"))
  expect_true(is.list(res$candidates))
})

test_that("cog_gov_search basket mode skips ambiguous and no_match rows", {
  skip_if_no_corpus()
  basket <- suppressMessages(cog_gov_search(
    name  = c("Broward",        "San Diego", "Notarealplace"),
    state = c("FL",             "CA",        "NY")
  ))
  # Broward resolves; San Diego ambiguous; Notarealplace no_match.
  expect_equal(nrow(basket), 1L)
  expect_equal(basket$canonical_govid, "121011212191")
  res <- attr(basket, "resolution")
  expect_equal(nrow(res), 3L)
  expect_equal(res$status, c("resolved", "ambiguous", "no_match"))
})

test_that("cog_gov_search basket mode preserves input order", {
  skip_if_no_corpus()
  basket <- cog_gov_search(
    name  = c("AUSTIN CITY", "BROWARD COUNTY", "SAN DIEGO CITY"),
    state = c("TX",          "FL",             "CA")
  )
  expect_equal(basket$gov_name, c("AUSTIN CITY", "BROWARD COUNTY", "SAN DIEGO CITY"))
})

test_that("cog_gov_search basket mode recycles single state", {
  skip_if_no_corpus()
  basket <- cog_gov_search(
    name  = c("SAN DIEGO CITY", "OAKLAND CITY"),
    state = "CA"
  )
  expect_equal(nrow(basket), 2L)
  expect_equal(basket$canonical_govid, c("062073207598", "062001123093"))
})

test_that("cog_gov_search basket mode within-type largest_pop records candidates", {
  skip_if_no_corpus()
  # `type = "city"` for the Miami row pins the match set to govs_type = 2;
  # under Phase P canonical naming MIAMI-DADE COUNTY also contains "Miami"
  # and would otherwise make this an ambiguous (cross-type) match.
  basket <- suppressMessages(cog_gov_search(
    name  = c("Miami",  "OAKLAND CITY"),
    state = c("FL",     "CA"),
    type  = c("city",   NA)
  ))
  expect_equal(nrow(basket), 2L)
  res <- attr(basket, "resolution")
  miami_row <- res[res$query_name == "Miami", ]
  expect_equal(miami_row$status, "largest_pop")
  expect_equal(miami_row$canonical_govid, "122086194757")
  expect_gte(miami_row$n_candidates, 2L)
  expect_gte(nrow(miami_row$candidates[[1]]), 2L)
})

test_that("cog_gov_search utility mode (length-1 name) has no sidecar", {
  skip_if_no_corpus()
  r <- cog_gov_search("BROWARD")
  expect_null(attr(r, "resolution"))
  expect_gte(nrow(r), 1L)
})

test_that("cog_gov_search basket mode validates argument lengths", {
  expect_error(
    cog_gov_search(
      name  = c("Broward", "San Diego", "Austin"),
      state = c("FL", "CA")
    ),
    regexp = "must be length 1 or 3"
  )
})

# ---- basket mode summary message ----

test_that("cog_gov_search basket mode is silent on clean basket", {
  skip_if_no_corpus()
  expect_message(
    cog_gov_search(
      name  = c("BROWARD COUNTY", "SAN DIEGO CITY"),
      state = c("FL",             "CA")
    ),
    regexp = NA  # NA = expect no message
  )
})

test_that("cog_gov_search basket mode reports breakdown on partial basket", {
  skip_if_no_corpus()
  expect_message(
    cog_gov_search(
      name  = c("Broward", "San Diego", "Notarealplace"),
      state = c("FL",      "CA",        "NY")
    ),
    regexp = "Basket resolved 1 of 3"
  )
})

test_that("cog_gov_search basket mode message points to the sidecar accessor", {
  skip_if_no_corpus()
  expect_message(
    cog_gov_search(
      name  = c("Broward", "Notarealplace"),
      state = c("FL",      "NY")
    ),
    regexp = "cog_basket_resolution"
  )
})

# ---- F1: per-row excluded type soft-fail ----

test_that(".resolve_basket_row treats excluded type as no_match (not abort)", {
  con <- uscogdata:::.ensure_session()
  out <- uscogdata:::.resolve_basket_row(
    name = "Some District", state = "CA", type = "special_district", con = con
  )
  expect_equal(out$status, "no_match")
  expect_true(is.na(out$match_method))
  expect_equal(out$n_candidates, 0L)
})

test_that("cog_gov_search basket mode skips per-row excluded type without aborting", {
  basket <- suppressMessages(cog_gov_search(
    name  = c("BROWARD COUNTY", "Some District"),
    state = c("FL",             "FL"),
    type  = c(NA,                "special_district")
  ))
  # Broward should resolve; the special_district row should be no_match.
  expect_equal(nrow(basket), 1L)
  expect_equal(basket$canonical_govid, "121011212191")
  res <- attr(basket, "resolution")
  expect_equal(res$status, c("resolved", "no_match"))
  # query_type should record what the user passed for the excluded-type row
  expect_equal(res$query_type, c(NA_character_, "special_district"))
})

# ---- F2: malformed regex name soft-fail ----

test_that(".resolve_basket_row treats malformed regex name as no_match", {
  con <- uscogdata:::.ensure_session()
  # Unbalanced parens would be a regex parse error if not escaped.
  out <- uscogdata:::.resolve_basket_row(
    name = "San(Diego", state = "CA", type = NA_character_, con = con
  )
  expect_equal(out$status, "no_match")
})

test_that(".resolve_basket_row escapes regex metacharacters in name", {
  con <- uscogdata:::.ensure_session()
  # Confirm that names with various metacharacters don't error.
  expect_no_error(uscogdata:::.resolve_basket_row(
    name = "Foo*Bar+Baz", state = "FL", type = NA_character_, con = con
  ))
})

# ---- F3: all-no-match basket public surface ----

test_that("cog_gov_search basket all-no-match returns 0-row tibble with full sidecar", {
  basket <- suppressMessages(cog_gov_search(
    name  = c("Notarealplace1", "Notarealplace2"),
    state = c("NY",             "CA")
  ))
  expect_equal(nrow(basket), 0L)
  expect_true("canonical_govid" %in% names(basket))
  res <- attr(basket, "resolution")
  expect_equal(nrow(res), 2L)
  expect_true(all(res$status == "no_match"))
})
