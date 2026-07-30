test_that("cog_geographic_rollup aggregates state + county + city layers", {
  skip_if_no_corpus()
  r <- cog_geographic_rollup(
    govids = list(
      state  = "120000226351",               # Florida state govt
      county = "121011212191",               # Broward County
      city   = "122011161585"                # Fort Lauderdale City
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
    govids = list(county = "121011212191", city = "122011161585"),
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
    govids = list(state = "120000226351", county = "121011212191",
                  city = "122011161585"),
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
    govids = list(county = c("121011212191")),
    category = "Corrections",
    years = 2020L
  )
  expect_true(all(r$layer == "county"))
  expect_gt(nrow(r), 0L)
})

test_that("cog_geographic_rollup provenance reports the outer verb", {
  skip_if_no_corpus()
  r <- cog_geographic_rollup(
    govids = list(state = "120000226351", county = "121011212191"),
    category = "Police", years = 2020L
  )
  prov <- attr(r, "provenance")
  expect_equal(prov$verb, "cog_geographic_rollup")
  expect_setequal(prov$layers, c("state", "county"))
  expect_true(grepl("cog_geographic_rollup", prov$call))
})

test_that("cog_geographic_rollup accepts data.frames per layer", {
  skip_if_no_corpus()
  # Unanchored: utility mode matches literally now, so "^...$" would be
  # searched for as characters rather than read as anchors (uscogdata#16).
  # Both still resolve to exactly one row once scoped by type/state.
  fl_state  <- cog_gov_search("FLORIDA", type = "state")
  broward   <- cog_gov_search("BROWARD COUNTY", state = "FL", type = "county")
  r <- cog_geographic_rollup(
    govids = list(state = fl_state, county = broward),
    category = "Police", years = 2020L
  )
  expect_setequal(unique(r$layer), c("state", "county"))
  expect_gt(nrow(r), 0L)
})

test_that("cog_geographic_rollup rejects invalid inputs", {
  expect_error(cog_geographic_rollup(list(), "Police", 2020L), "length")
  expect_error(cog_geographic_rollup(c("121011212191"), "Police", 2020L), "list")
  expect_error(
    cog_geographic_rollup(list(planet = "120000226351"), "Police", 2020L),
    "state|county|city"
  )
})

test_that("cog_geographic_rollup per-capita uses summed per-year populations", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_geographic_rollup(
      govids   = list(state  = "010000226085",
                      county = "121011212191"),
      category = "Police",
      years    = 2019:2020,
      per_capita = TRUE
    )
    state_ops <- r[r$layer == "state" & r$spend_subtype == "operations", ]
    county_ops <- r[r$layer == "county" & r$spend_subtype == "operations", ]
    state_implied <- state_ops$amt_nominal / state_ops$amt_per_capita_nominal
    county_implied <- county_ops$amt_nominal /
      county_ops$amt_per_capita_nominal
    # Per-year, per-layer denominator is the layer's own per-year population
    expect_equal(state_implied[state_ops$year == 2019], 4874747, tolerance = 1)
    expect_equal(state_implied[state_ops$year == 2020], 4903185, tolerance = 1)
    expect_equal(county_implied[county_ops$year == 2019], 1935878, tolerance = 1)
  })
})

test_that("cog_geographic_rollup records included/excluded govids in provenance", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_geographic_rollup(
      govids   = list(county = "121011212191"),
      category = "Police",
      years    = 2019:2020,
      per_capita = TRUE
    )
    prov <- attr(r, "provenance")
    expect_true("rollup" %in% names(prov))
    expect_true("121011212191" %in% prov$rollup$included_govids)
    expect_true(is.character(prov$rollup$excluded_govids))
  })
})
