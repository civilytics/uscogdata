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

test_that("inst/sql/22- and 23- harmonized views enforce every WHERE predicate (real SQL text, synthetic parquet)", {
  # spending_long_harmonized / revenue_long_harmonized are three-predicate
  # views:
  #   SELECT * REPLACE (harmonized_code AS item_code)
  #   FROM long
  #   WHERE NOT is_aggregate
  #     AND harmonized_code IS NOT NULL
  #     AND LEFT(harmonized_code, 1) IN (<flow prefixes>)
  # None of the curated harmonization_map's `collapse` rulings land inside
  # the bundled fixture's 2011-2020 window for spending/revenue-prefixed
  # codes (see the "basis = 'harmonized' (default) matches 'raw'" test in
  # test-spending.R and docs/phase_r_harmonization_review.md § 0.2/§ 2), so
  # there is no real fixture row that exercises a nonzero fold or a
  # predicate-excluded row. Rather than re-implement the WHERE clause by
  # hand against an in-memory VALUES table (which would only prove the SQL
  # *pattern* works, not that the deployed inst/sql/22-/23- text actually
  # applies it), this test reads the real SQL files off disk, substitutes
  # {url} exactly as .register_views() does, and executes them -- plus
  # their 10-long.sql dependency -- against a synthetic hive-partitioned
  # parquet tree written to a temp dir. A regression in any predicate (e.g.
  # `NOT is_aggregate` dropped, the prefix list changed, the NULL guard
  # removed) would change which of the rows below survive.
  #
  # The synthetic parquet is written with DuckDB's own COPY ... TO (FORMAT
  # PARQUET) rather than the arrow package: this package has no arrow
  # dependency (CLAUDE.md "No arrow dependency -- DuckDB reads parquet
  # natively"), and DuckDB can round-trip its own parquet writer/reader
  # without adding one for tests either.
  skip_if_no_corpus()

  tmp <- withr::local_tempdir()
  part_dir <- file.path(tmp, "data", "long", "year=2004")
  dir.create(part_dir, recursive = TRUE)
  part_path <- file.path(part_dir, "part-0.parquet")

  write_con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(write_con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(write_con, sprintf("
    COPY (
      SELECT * FROM (VALUES
        -- Spending (E/F/G/K) rows, exercised against spending_long_harmonized:
        ('spend-A', 'E36', 100,    false, 'E36'), -- control: passes every predicate as-is
        ('spend-B', 'E38', 50,     false, 'E36'), -- collapse-fold: passes every predicate, renamed to E36
        ('spend-C', 'E05', 999999, true,  'E05'), -- excluded ONLY by `NOT is_aggregate`
        ('spend-D', 'E99', 888888, false, NULL),  -- excluded by `harmonized_code IS NOT NULL`
        -- 'S74' is outside BOTH flow families (E/F/G/K spending and
        -- T/A/U/B/C/D revenue -- it mirrors the real corpus's own
        -- non-flow-type codes like S74/Z61), so it can only leak into
        -- EITHER view via the E/F/G/K or T/A/U/B/C/D prefix filter, never
        -- both at once -- a prefix drawn from the other view's own family
        -- (e.g. a real T-code for the spending row) would incorrectly
        -- leak into the other view's assertion below and not discriminate
        -- the predicate under test.
        ('spend-E', 'S74', 777777, false, 'S74'), -- excluded ONLY by the E/F/G/K prefix filter
        -- Revenue (T/A/U/B/C/D) rows, exercised against revenue_long_harmonized:
        ('rev-A',   'U11', 200,    false, 'U11'), -- control: passes every predicate as-is
        ('rev-B',   'U10', 25,     false, 'U11'), -- collapse-fold: passes every predicate, renamed to U11
        ('rev-C',   'T29', 555555, true,  'T29'), -- excluded ONLY by `NOT is_aggregate`
        ('rev-D',   'T88', 444444, false, NULL),  -- excluded by `harmonized_code IS NOT NULL`
        ('rev-E',   'Z61', 333333, false, 'Z61')  -- excluded ONLY by the T/A/U/B/C/D prefix filter
      ) AS t(canonical_govid, item_code, amt, is_aggregate, harmonized_code)
    ) TO %s (FORMAT PARQUET)
  ", uscogdata:::.sql_lit_chr(part_path)))

  sql_dir <- system.file("sql", package = "uscogdata")
  .read_view_sql <- function(filename) {
    txt <- paste(readLines(file.path(sql_dir, filename), warn = FALSE), collapse = "\n")
    gsub("\\{url\\}", paste0(tmp, "/"), txt, fixed = FALSE)
  }

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, .read_view_sql("10-long.sql"))
  DBI::dbExecute(con, .read_view_sql("22-spending_long_harmonized.sql"))
  DBI::dbExecute(con, .read_view_sql("23-revenue_long_harmonized.sql"))

  spend <- DBI::dbGetQuery(con,
    "SELECT item_code, SUM(amt) AS amt FROM spending_long_harmonized
     GROUP BY item_code ORDER BY item_code"
  )
  # Exactly one surviving row: spend-C (aggregate), spend-D (NULL
  # harmonized_code), and spend-E (wrong prefix family) must all be gone,
  # and spend-A + spend-B must be folded together under E36.
  expect_equal(nrow(spend), 1L)
  expect_equal(spend$item_code, "E36")
  expect_equal(spend$amt, 150)

  rev <- DBI::dbGetQuery(con,
    "SELECT item_code, SUM(amt) AS amt FROM revenue_long_harmonized
     GROUP BY item_code ORDER BY item_code"
  )
  expect_equal(nrow(rev), 1L)
  expect_equal(rev$item_code, "U11")
  expect_equal(rev$amt, 225)
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
