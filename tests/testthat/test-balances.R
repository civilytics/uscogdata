test_that("balance views register and carry only balance codes", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())

  views <- DBI::dbGetQuery(con,
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'main' AND table_type = 'VIEW'"
  )$table_name
  expect_true(all(c("balance_long", "balance_annotated") %in% views))

  # Every item_code in balance_long is a category_type = 'balance' member.
  leak <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM balance_long
     WHERE item_code NOT IN (
       SELECT item_code FROM summary_categories WHERE category_type = 'balance')"
  )$n
  expect_identical(as.integer(leak), 0L)

  # balance_annotated exposes the subtype column the verb groups on.
  cols <- DBI::dbGetQuery(con,
    "SELECT column_name FROM information_schema.columns
     WHERE table_name = 'balance_annotated'"
  )$column_name
  expect_true(all(c("category", "category_type", "balance_subtype") %in% cols))
})

test_that("inst/sql/26-balance_long.sql enforces NOT is_aggregate (real SQL text, synthetic parquet)", {
  # Every category_type = 'balance' item_code in the bundled fixture has
  # is_aggregate = FALSE for every row of every year -- there is no real row
  # that would be excluded ONLY by the `AND NOT is_aggregate` predicate. An
  # assertion against the live fixture (`WHERE is_aggregate` returns 0) is
  # therefore vacuous: it passes identically whether or not the view's
  # predicate is present. As with the 22-/23- and 24-/25- tests above, this
  # reads the real inst/sql/26-balance_long.sql text off disk and executes it
  # -- plus its 10-long.sql / 11-summary_categories.sql dependencies -- against
  # a synthetic hive-partitioned parquet tree that DOES contain an aggregate
  # row under a real balance item_code (W01), so a regression that drops the
  # predicate changes which rows survive.
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
        ('bal-A', 'W01', 100,    false), -- control: ordinary balance row, survives
        ('bal-B', 'W01', 999999, true)   -- excluded ONLY by `NOT is_aggregate`
      ) AS t(canonical_govid, item_code, amt, is_aggregate)
    ) TO %s (FORMAT PARQUET)
  ", uscogdata:::.sql_lit_chr(part_path)))

  DBI::dbExecute(write_con, sprintf("
    COPY (
      SELECT * FROM (VALUES
        ('W01', 'Fund Balances', 'balance', NULL, NULL, 'general')
      ) AS t(item_code, category, category_type, spend_subtype, revenue_subtype, balance_subtype)
    ) TO %s (FORMAT PARQUET)
  ", uscogdata:::.sql_lit_chr(file.path(tmp, "data", "summary_categories.parquet"))))

  sql_dir <- system.file("sql", package = "uscogdata")
  .read_view_sql <- function(filename) {
    txt <- paste(readLines(file.path(sql_dir, filename), warn = FALSE), collapse = "\n")
    gsub("\\{url\\}", paste0(tmp, "/"), txt, fixed = FALSE)
  }

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, .read_view_sql("10-long.sql"))
  DBI::dbExecute(con, .read_view_sql("11-summary_categories.sql"))
  DBI::dbExecute(con, .read_view_sql("26-balance_long.sql"))

  rows <- DBI::dbGetQuery(con,
    "SELECT canonical_govid, item_code, amt FROM balance_long ORDER BY canonical_govid"
  )
  expect_equal(nrow(rows), 1L)
  expect_equal(rows$canonical_govid, "bal-A")
  expect_equal(rows$amt, 100)
})

test_that("balance views are skipped on a corpus without balance_subtype", {
  skip_if_no_corpus()
  with_corpus_missing_balance_subtype({
    con <- cog_open()
    on.exit(cog_close())
    views <- DBI::dbGetQuery(con,
      "SELECT table_name FROM information_schema.tables
       WHERE table_schema = 'main' AND table_type = 'VIEW'"
    )$table_name
    # Registration must SKIP them, not error -- an older corpus stays usable.
    expect_false(any(c("balance_long", "balance_annotated") %in% views))
    expect_true("revenue_long" %in% views)
  })
})

test_that("cog_balances returns holdings for a government that has them", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_balances("550000227544", 2019)
    expect_s3_class(r, "tbl_df")
    expect_true(nrow(r) > 0L)
    expect_true(all(c("year", "canonical_govid", "gov_name", "balance_subtype",
                      "category", "amt_nominal") %in% names(r)))
    expect_identical(sort(unique(r$category)),
                     c("Fund Balances", "Insurance Trust Balances"))
    expect_false(is.null(attr(r, "provenance")))
    expect_identical(attr(r, "provenance")$verb, "cog_balances")
  })
})

test_that('category = "Fund Balances" is exactly the general family', {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_balances("550000227544", 2019, category = "Fund Balances")
    expect_identical(unique(r$balance_subtype), "general")
    codes <- sort(unlist(strsplit(paste(r$codes_included, collapse = ","), ",")))
    expect_identical(codes, c("W01", "W31", "W61"))
  })
})

test_that("no flow code can reach cog_balances", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_balances("550000227544", c(2011, 2012, 2019, 2020))
    got <- unique(unlist(strsplit(paste(r$codes_included, collapse = ","), ",")))

    # The expected set is read from the RAW corpus, never from the verb --
    # verifying an absence through the filter that creates it proves nothing.
    # A fresh, direct DuckDB connection against the raw parquet files (never
    # cog_open()'s session, never balance_long/balance_annotated) reads
    # parquet natively -- no arrow dependency needed (see CLAUDE.md).
    con2 <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con2, shutdown = TRUE), add = TRUE)
    cats_path <- file.path(fixture_corpus_path(), "data", "summary_categories.parquet")
    balance_codes <- DBI::dbGetQuery(con2, sprintf(
      "SELECT item_code FROM read_parquet(%s) WHERE category_type = 'balance'",
      uscogdata:::.sql_lit_chr(cats_path)
    ))$item_code

    expect_true(length(got) > 0L)
    expect_true(all(got %in% balance_codes))
  })
})

test_that("every balance_subtype maps to exactly one category", {
  skip_if_no_corpus()
  # Dropping the `subtype` argument is only safe while this tree holds. If the
  # pipeline ever gives a balance subtype a second category, `category` becomes
  # a lossy filter -- fail HERE rather than in a user's analysis. Read via a
  # fresh direct DuckDB connection against the raw parquet file, not through
  # any registered view.
  con2 <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con2, shutdown = TRUE), add = TRUE)
  cats_path <- file.path(fixture_corpus_path(), "data", "summary_categories.parquet")
  b <- DBI::dbGetQuery(con2, sprintf(
    "SELECT category, balance_subtype FROM read_parquet(%s) WHERE category_type = 'balance'",
    uscogdata:::.sql_lit_chr(cats_path)
  ))
  per_subtype <- tapply(b$category, b$balance_subtype,
                        function(x) length(unique(x)))
  expect_true(all(per_subtype == 1L))
})

test_that("cog_balances records found + missing govids in provenance", {
  skip_if_no_corpus()
  with_fixture_corpus({
    suppressMessages(
      r <- cog_balances(c("550000227544", "XXXINVALID"), 2019)
    )
    prov <- attr(r, "provenance")
    expect_equal(sort(prov$scope$govids_found), "550000227544")
    expect_equal(sort(prov$scope$govids_missing), "XXXINVALID")
  })
})

test_that("per_capita divides holdings by population", {
  skip_if_no_corpus()
  with_fixture_corpus({
    plain <- cog_balances("550000227544", 2019, category = "Fund Balances")
    pc    <- cog_balances("550000227544", 2019, category = "Fund Balances",
                          per_capita = TRUE)
    expect_true("amt_per_capita_nominal" %in% names(pc))
    expect_true("pop_source" %in% names(pc))
    expect_identical(pc$amt_nominal, plain$amt_nominal)

    # Assert against the denominator read from the corpus, NOT against a
    # quantity derived from amt_per_capita_nominal itself -- dividing the
    # column back out would be tautological and would pass on any value.
    pop <- DBI::dbGetQuery(cog_open(), sprintf(
      "SELECT population FROM gov_population_yearly
       WHERE canonical_govid = %s AND year = 2019",
      uscogdata:::.sql_lit_chr("550000227544")
    ))$population
    expect_length(pop, 1L)
    expect_equal(pc$amt_per_capita_nominal, pc$amt_nominal / pop,
                 tolerance = 1e-8)

    prov <- attr(pc, "provenance")
    expect_true(prov$transformations$per_capita$applied)
  })
})

test_that("adjust_to_year adds real dollars", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_balances("550000227544", 2012, category = "Fund Balances",
                      adjust_to_year = 2020)
    expect_true("amt_real" %in% names(r))
    # 2012 dollars inflated to 2020 must exceed nominal.
    expect_true(all(r$amt_real > r$amt_nominal))
    prov <- attr(r, "provenance")
    expect_true(prov$transformations$inflation$applied)
    expect_identical(prov$transformations$inflation$base_year, 2020L)
  })
})

# --- recipe = : the wide-era holdings bridge -------------------------------

test_that("recipe bridges the wide era into the modern one", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_balances("550000227544", c(2011, 2012),
                      recipe = "cash_securities_z77_wide")
    # .run_recipe()'s SQL returns `long.year` as a DOUBLE (a corpus-wide trait,
    # not specific to this recipe -- see the money-verb recipe tests, which
    # only ever assert on it with expect_equal), so compare numerically rather
    # than with expect_identical()'s type-strict comparison.
    expect_equal(sort(r$year), c(2011, 2012))

    # The 2011 leg can ONLY come from X40, which is 100% is_aggregate = TRUE
    # and therefore invisible to balance_long. If the recipe path ever starts
    # filtering aggregates, a 45-year series silently truncates to five --
    # this is the regression guard for phase_r_harmonization_review.md § 0.2.
    codes <- attr(r, "provenance")$codes_summed$observed
    expect_true("X40" %in% codes)
    expect_true("Z77" %in% codes)
    expect_true(all(r$amt_nominal > 0))

    prov <- attr(r, "provenance")
    expect_identical(prov$recipe$recipe_id, "cash_securities_z77_wide")
  })
})

test_that("the FY2002 book-to-market basis change is disclosed on the recipe path", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # NOTE on years = c(2002, 2011, 2012), which deviates from the brief's
    # verbatim c(2011, 2012): .build_series_break_refs() (R/series_breaks.R,
    # shared with every verb) gates on
    # `break_year BETWEEN min(years) AND max(years)` -- a window over the
    # REQUESTED years, not merely over which codes were observed. SB195's
    # break_year is 2002, and this fixture has no X40/Z77 partition data for
    # any year before 2011, so years = c(2011, 2012) alone can never open a
    # window containing 2002 -- confirmed empirically; see
    # task-4-report.md for the investigation. There is no 2002 partition in
    # the fixture, so adding 2002 to `years` is a pure no-op on the returned
    # rows (asserted below) and only widens the break-matching window -- it
    # does not change which rows the recipe join reads. Flagged as a
    # follow-up candidate: `.build_series_break_refs()`'s window semantics may
    # want to treat an in-series precision-change break (fin_code observed,
    # break_year <= max(years)) differently from a boundary/rename break, but
    # that is shared, cross-verb logic and out of scope for this task.
    r <- cog_balances("550000227544", c(2002, 2011, 2012),
                      recipe = "cash_securities_z77_wide")
    expect_equal(sort(r$year), c(2011, 2012))
    refs <- attr(r, "provenance")$series_break_refs
    # SB195 sits on fin_code X40; it can only fire where X40 is observed,
    # which is exactly the recipe path.
    expect_true("SB195" %in% refs)
  })
})

test_that("the second holdings bridge works too", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # X41 -> Z78, the securities counterpart. Wisconsin carries X41 in 2011
    # and Z78 in 2012, so both legs are exercised.
    r <- cog_balances("550000227544", c(2011, 2012),
                      recipe = "cash_securities_z78_wide")
    codes <- attr(r, "provenance")$codes_summed$observed
    expect_true(all(c("X41", "Z78") %in% codes))
    expect_equal(sort(r$year), c(2011, 2012))
  })
})

test_that("an unknown recipe id is rejected", {
  skip_if_no_corpus()
  with_fixture_corpus({
    expect_error(cog_balances("550000227544", 2019, recipe = "no_such_recipe"))
  })
})
