# tests/testthat/test-http-metadata-cache.R
#
# uscogdata#64. On the remote path every CREATE VIEW re-requested the same
# file metadata over HTTP: 23 views at about 0.35 s each made session open
# take about 6 s against the public corpus. DuckDB's HTTP metadata cache keeps
# those responses for the life of the connection. Measured on 2026-11-12
# against the Hugging Face corpus, one run per arm: session open 5.6 s ->
# 1.6 s, first one-year query 1.2 s -> 0.8 s, the same query again
# 0.55 s -> 0.02 s.
#
# The fixture is local, so these tests can only check that the setting is on,
# not that it saves anything.

test_that("cog_open() turns on DuckDB's HTTP metadata cache (#64)", {
  skip_if_no_corpus()
  uscogdata:::cog_close()
  on.exit(uscogdata:::cog_close(), add = TRUE)
  con <- uscogdata:::cog_open()
  v <- DBI::dbGetQuery(
    con, "SELECT current_setting('enable_http_metadata_cache') AS v"
  )$v[[1]]
  expect_true(isTRUE(as.logical(v)))
})
