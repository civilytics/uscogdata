test_that("all expected views register on session open", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  views <- DBI::dbGetQuery(con,
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'main' AND table_type = 'VIEW'"
  )
  expected <- c(
    "long", "spending_long", "revenue_long",
    "canonical_fips_xwalk", "summary_categories",
    "spending_annotated", "revenue_annotated"
  )
  expect_true(all(expected %in% views$table_name))
})

test_that("the REPLACE(harmonized_code AS item_code) pattern folds a collapsed code", {
  # spending_long_harmonized / revenue_long_harmonized (inst/sql/22-, 23-)
  # are defined as:
  #   SELECT * REPLACE (harmonized_code AS item_code) FROM long WHERE ...
  # None of the curated harmonization_map's `collapse` rulings land inside
  # the bundled fixture's 2011-2020 window for spending/revenue-prefixed
  # codes (see the "basis = 'harmonized' (default) matches 'raw'" test in
  # test-spending.R and docs/phase_r_harmonization_review.md § 0.2/§ 2), so
  # there is no real fixture row that exercises a nonzero fold. This test
  # proves the REPLACE mechanism itself is correct against a synthetic
  # long-shaped table with a deliberate E38 -> E36 collapse, independent of
  # whether the bundled data happens to contain one right now.
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())

  DBI::dbExecute(con, "
    CREATE OR REPLACE TEMP TABLE synthetic_long AS
    SELECT * FROM (VALUES
      ('121011212191', 2004, 'E36', 70942668, false, 'E36'),
      ('121011212191', 2004, 'E38',   837485, false, 'E36'),
      ('121011212191', 2004, 'E62',   100000, false, 'E62')
    ) AS t(canonical_govid, year, item_code, amt, is_aggregate, harmonized_code)
  ")

  folded <- DBI::dbGetQuery(con, "
    SELECT item_code, SUM(amt) AS amt
    FROM (SELECT * REPLACE (harmonized_code AS item_code) FROM synthetic_long)
    GROUP BY item_code ORDER BY item_code
  ")
  expect_setequal(folded$item_code, c("E36", "E62"))
  expect_equal(folded$amt[folded$item_code == "E36"], 70942668 + 837485)
  expect_equal(folded$amt[folded$item_code == "E62"], 100000)

  DBI::dbExecute(con, "DROP TABLE synthetic_long")
})

test_that(".build_series_break_refs matches fin_code + break_year window", {
  # No series_breaks_pq row falls inside the bundled fixture's 2011-2020
  # window (data-verified; see the "series_break_refs" test in
  # test-spending.R), so this proves the matching logic itself against the
  # live view + a synthetic year window that DOES hit a cataloged break
  # (SB075, fin_code E62, break_year 2005).
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  refs <- uscogdata:::.build_series_break_refs(
    con, codes_observed = c("E62", "E04"), years = c(2003L, 2006L),
    schema_version = 5L
  )
  expect_true("SB075" %in% refs)
  expect_true("SB071" %in% refs)

  # Gated on schema_version >= 5 even when the codes/years would otherwise match.
  refs_v4 <- uscogdata:::.build_series_break_refs(
    con, codes_observed = c("E62"), years = c(2003L, 2006L), schema_version = 4L
  )
  expect_equal(refs_v4, character(0))
})

test_that("schema v5 harmonization views register when the corpus supports them", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  manifest <- uscogdata:::.uscogdata_env$manifest
  skip_if(as.integer(manifest$schema_version) < 5L, "fixture is schema_version < 5")

  views <- DBI::dbGetQuery(con,
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'main' AND table_type = 'VIEW'"
  )
  expected_v5 <- c(
    "spending_long_harmonized", "revenue_long_harmonized",
    "spending_annotated_harmonized", "revenue_annotated_harmonized",
    "harmonization_map", "harmonization_recipes", "series_breaks_pq"
  )
  expect_true(all(expected_v5 %in% views$table_name))
})

test_that("spending_long filters to E/F/G/K prefixes and excludes aggregates", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  prefixes <- DBI::dbGetQuery(con,
    "SELECT DISTINCT LEFT(item_code, 1) AS pfx FROM spending_long"
  )$pfx
  expect_true(all(prefixes %in% c("E", "F", "G", "K")))

  agg_count <- DBI::dbGetQuery(con,
    "SELECT count(*) AS n FROM spending_long WHERE is_aggregate"
  )$n
  expect_equal(agg_count, 0)
})

test_that("revenue_long filters to T/A/U/B/C/D prefixes and excludes aggregates", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  prefixes <- DBI::dbGetQuery(con,
    "SELECT DISTINCT LEFT(item_code, 1) AS pfx FROM revenue_long"
  )$pfx
  expect_true(all(prefixes %in% c("T", "A", "U", "B", "C", "D")))

  agg_count <- DBI::dbGetQuery(con,
    "SELECT count(*) AS n FROM revenue_long WHERE is_aggregate"
  )$n
  expect_equal(agg_count, 0)
})

test_that("spending_annotated carries category + xwalk columns", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())
  row <- DBI::dbGetQuery(con,
    "SELECT * FROM spending_annotated LIMIT 1"
  )
  for (nm in c("canonical_govid", "item_code", "amt",
               "xwalk_gov_name", "govs_type", "population_acs",
               "category", "spend_subtype")) {
    expect_true(nm %in% names(row), info = paste("missing column:", nm))
  }
})

test_that("gov_population_yearly exposes one row per (year, canonical_govid)", {
  skip_if_no_corpus()
  with_fixture_corpus({
    con <- uscogdata:::.ensure_session()
    df <- DBI::dbGetQuery(
      con,
      "SELECT year, canonical_govid, population, popyear
       FROM gov_population_yearly
       WHERE canonical_govid = '121011212191'
       ORDER BY year"
    )
    expect_setequal(df$year, c(2011L, 2012L, 2019L, 2020L))
    expect_equal(nrow(df), 4L)
    expect_true(all(!is.na(df$population)))
    # Hardcoded values are from the bundled fixture (regenerated 2026-07-18
    # against cog_pipeline publish tree, pipeline_commit ece9b32, Phase R2
    # schema_version 5, years 2011/2012/2019/2020). Update if the fixture is
    # rebuilt against a different source vintage.
    expect_equal(df$population[df$year == 2011L], 1759591L)
    expect_equal(df$population[df$year == 2012L], 1819773L)
    expect_equal(df$population[df$year == 2019L], 1935878L)
    expect_equal(df$population[df$year == 2020L], 1952778L)
    # Uniqueness on (year, canonical_govid) across the whole view.
    dup <- DBI::dbGetQuery(
      con,
      "SELECT year, canonical_govid, COUNT(*) AS n
       FROM gov_population_yearly
       GROUP BY year, canonical_govid HAVING n > 1"
    )
    expect_equal(nrow(dup), 0L)
  })
})
