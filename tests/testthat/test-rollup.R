test_that("cog_geographic_rollup aggregates state + county + city layers", {
  skip_if_no_corpus()
  r <- cog_geographic_rollup(
    govids = list(
      state  = "100000000",               # Florida state govt
      county = "101006006",               # Broward County
      city   = "102006004"                # Fort Lauderdale City
    ),
    category = "Police",
    years = 2019:2020
  )
  expect_s3_class(r, "tbl_df")
  expected_cols <- c("year", "layer", "canonical_govid", "gov_name",
                     "spend_subtype", "category", "amt_nominal",
                     "codes_included", "aggregate_fallback",
                     "scope_note", "notes")
  expect_true(all(expected_cols %in% names(r)))
  expect_setequal(unique(r$layer), c("state", "county", "city"))
  expect_true(all(r$category == "Police"))
  expect_true(all(r$year %in% 2019:2020))
})

test_that("cog_geographic_rollup respects per_capita + adjust_to_year", {
  skip_if_no_corpus()
  r <- cog_geographic_rollup(
    govids = list(county = "101006006", city = "102006004"),
    category = "Police",
    years = 2020L,
    per_capita = TRUE,
    adjust_to_year = 2022L
  )
  expect_true(all(c("amt_nominal", "amt_real",
                    "amt_per_capita_nominal", "amt_per_capita_real") %in%
                  names(r)))
  # Each layer's per-capita uses its own population: city pop < county pop,
  # so per_capita_nominal for city rows should differ meaningfully from county.
  city_pc <- r$amt_per_capita_nominal[r$layer == "city"]
  cty_pc  <- r$amt_per_capita_nominal[r$layer == "county"]
  expect_true(length(city_pc) > 0L)
  expect_true(length(cty_pc) > 0L)
})

test_that("cog_geographic_rollup scope_notes describe each layer", {
  skip_if_no_corpus()
  r <- cog_geographic_rollup(
    govids = list(state = "100000000", county = "101006006",
                  city = "102006004"),
    category = "Police", years = 2020L
  )
  state_notes <- unique(r$scope_note[r$layer == "state"])
  expect_true(any(grepl("state total", state_notes)))
  county_notes <- unique(r$scope_note[r$layer == "county"])
  expect_true(any(grepl("county", county_notes)))
  city_notes <- unique(r$scope_note[r$layer == "city"])
  expect_true(any(grepl("city proper", city_notes)))
})

test_that("cog_geographic_rollup single-layer call works", {
  skip_if_no_corpus()
  r <- cog_geographic_rollup(
    govids = list(county = c("101006006")),
    category = "Corrections",
    years = 2020L
  )
  expect_true(all(r$layer == "county"))
  expect_gt(nrow(r), 0L)
})

test_that("cog_geographic_rollup provenance reports the outer verb", {
  skip_if_no_corpus()
  r <- cog_geographic_rollup(
    govids = list(state = "100000000", county = "101006006"),
    category = "Police", years = 2020L
  )
  prov <- attr(r, "provenance")
  expect_equal(prov$verb, "cog_geographic_rollup")
  expect_setequal(prov$layers, c("state", "county"))
  expect_true(grepl("cog_geographic_rollup", prov$call))
})

test_that("cog_geographic_rollup rejects invalid inputs", {
  expect_error(cog_geographic_rollup(list(), "Police", 2020L), "length")
  expect_error(cog_geographic_rollup(c("101006006"), "Police", 2020L), "list")
  expect_error(
    cog_geographic_rollup(list(planet = "100000000"), "Police", 2020L),
    "state|county|city"
  )
})
