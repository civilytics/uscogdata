test_that(".long_files_sql enumerates every partition the manifest lists", {
  manifest <- list(files = list(long_partitions = list(
    list(year = 2011L, path = "data/long/year=2011/part-0.parquet"),
    list(year = 2012L, path = "data/long/year=2012/part-0.parquet")
  )))
  expect_equal(
    uscogdata:::.long_files_sql("https://example.org/corpus/", manifest),
    paste0(
      "['https://example.org/corpus/data/long/year=2011/part-0.parquet',",
      "'https://example.org/corpus/data/long/year=2012/part-0.parquet']"
    )
  )
})

test_that(".long_files_sql falls back to the glob when no partition list is present", {
  # test-views.R registers views with a hand-built manifest that has no
  # `files` element. That must keep working: the glob is valid for the
  # local paths such a manifest is used with.
  expect_equal(
    uscogdata:::.long_files_sql("/tmp/corpus/", list(schema_version = 4L)),
    "'/tmp/corpus/data/long/**/*.parquet'"
  )
  expect_equal(
    uscogdata:::.long_files_sql("/tmp/corpus/", list(files = list(long_partitions = list()))),
    "'/tmp/corpus/data/long/**/*.parquet'"
  )
})

test_that("the enumerated list matches the bundled fixture's partition count", {
  skip_if_no_corpus()
  m <- jsonlite::fromJSON(
    file.path(fixture_corpus_path(), "manifest.json"), simplifyVector = FALSE
  )
  out <- uscogdata:::.long_files_sql(fixture_corpus_path(), m)
  expect_equal(
    lengths(regmatches(out, gregexpr("part-0\\.parquet", out))),
    length(m$files$long_partitions)
  )
})

test_that("no view SQL survives rendering with an unsubstituted token", {
  # Introducing {long_files} broke four test sites that had hand-rolled the
  # {url} substitution -- each failed with a DuckDB parser error on the
  # surviving brace. This asserts the whole SQL directory renders clean, so
  # a future token cannot reintroduce that silently.
  sql_dir <- system.file("sql", package = "uscogdata")
  for (f in list.files(sql_dir, pattern = "\\.sql$", full.names = TRUE)) {
    rendered <- uscogdata:::.render_view_sql(
      paste(readLines(f, warn = FALSE), collapse = "\n"), "/tmp/corpus/"
    )
    expect_false(grepl("\\{[a-z_]+\\}", rendered), label = basename(f))
  }
})

test_that("registered `long` view reads through the enumerated list", {
  skip_if_no_corpus()
  with_fixture_corpus({
    con <- uscogdata:::.ensure_session()
    n <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM long")$n
    expect_gt(n, 0)
    yrs <- DBI::dbGetQuery(con, "SELECT DISTINCT year FROM long ORDER BY year")$year
    expect_true(all(c(2011, 2012, 2019, 2020) %in% yrs))
  })
})
