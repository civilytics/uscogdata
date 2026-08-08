# tests/testthat/test-manifest.R
#
# Tests for the guards on .fetch_or_cache_manifest() and cog_open() that
# protect users from silent failures when USCOGDATA_URL is misconfigured
# or returns non-JSON content.

test_that("cog_open aborts with actionable error when URL contains the sentinel", {
  uscogdata:::cog_close()
  on.exit(uscogdata:::cog_close(), add = TRUE)

  # No longer the package default (that is the public HF corpus). This is a
  # user who copied a config template and did not finish editing it.
  sentinel_url <- "https://cloud.civilytics.org/s/REPLACE_WITH_SHARE_TOKEN/download/"
  withr::with_envvar(c(USCOGDATA_URL = sentinel_url), {
    expect_error(
      uscogdata:::cog_open(),
      class = "uscogdata_url_not_configured"
    )
  })
})

test_that("placeholder guard fires for any URL containing the sentinel token", {
  uscogdata:::cog_close()
  on.exit(uscogdata:::cog_close(), add = TRUE)

  # Sentinel detection should be substring-based — covers any host that still
  # has REPLACE_WITH_SHARE_TOKEN baked in (default or partial user edit).
  withr::with_envvar(c(USCOGDATA_URL = "https://other.example/s/REPLACE_WITH_SHARE_TOKEN/x/"), {
    expect_error(
      uscogdata:::cog_open(),
      class = "uscogdata_url_not_configured"
    )
  })
})

test_that("placeholder guard error names both env var and option as remediation", {
  uscogdata:::cog_close()
  on.exit(uscogdata:::cog_close(), add = TRUE)

  # No longer the package default (that is the public HF corpus). This is a
  # user who copied a config template and did not finish editing it.
  sentinel_url <- "https://cloud.civilytics.org/s/REPLACE_WITH_SHARE_TOKEN/download/"
  withr::with_envvar(c(USCOGDATA_URL = sentinel_url), {
    msg <- tryCatch(uscogdata:::cog_open(), error = conditionMessage)
    expect_match(msg, "USCOGDATA_URL", fixed = TRUE)
    expect_match(msg, "uscogdata.url", fixed = TRUE)
  })
})

test_that("local manifest containing HTML produces uscogdata_invalid_manifest, not raw parse error", {
  uscogdata:::cog_close()
  on.exit(uscogdata:::cog_close(), add = TRUE)

  tmp <- withr::local_tempdir()
  writeLines(
    c("<html>", "  <head><title>Welcome to our server</title></head>", "</html>"),
    file.path(tmp, "manifest.json")
  )

  withr::with_envvar(c(USCOGDATA_URL = paste0(tmp, "/")), {
    err <- expect_error(
      uscogdata:::cog_open(),
      class = "uscogdata_invalid_manifest"
    )
    expect_match(conditionMessage(err), "manifest", ignore.case = TRUE)
  })
})

test_that("remote manifest fetch does not poison cache when response is HTML", {
  uscogdata:::cog_close()
  on.exit(uscogdata:::cog_close(), add = TRUE)

  tmp_cache <- withr::local_tempdir()
  cache_path <- file.path(tmp_cache, "manifest.json")

  # Pretend the cache already exists with stale-but-fresh-by-mtime HTML
  # (simulating a previous poisoned write from the old behavior). When the
  # fetcher sees invalid JSON in the cache, it must refetch rather than
  # silently returning a parse error to the caller.
  writeLines("<html>poisoned</html>", cache_path)
  Sys.setFileTime(cache_path, Sys.time())  # ensure within TTL

  # We don't have a live HTTP fixture here, so the refetch will fail at the
  # network layer — but the failure should NOT be a jsonlite parse error on
  # the cached HTML; it should be a network-level httr2 error. The cache
  # file itself must remain untouched (no atomic-write half-states).
  withr::with_envvar(
    c(
      USCOGDATA_URL = "https://invalid.localhost.uscogdata.test/",
      USCOGDATA_CACHE_DIR = tmp_cache
    ),
    {
      err <- tryCatch(uscogdata:::cog_open(), error = identity)
      expect_s3_class(err, "error")
      # Must not be a JSON lexical error on HTML.
      expect_false(grepl("lexical error", conditionMessage(err), fixed = TRUE))
    }
  )

  # Atomic write contract: no stray tmp files left behind in cache_dir.
  expect_length(
    list.files(tmp_cache, pattern = "manifest\\.json\\.tmp"),
    0L
  )
})

test_that("cog_manifest returns the active session's parsed manifest", {
  with_fixture_corpus({
    m <- cog_manifest()
    expect_type(m, "list")
    expect_true(m$schema_version >= 4L)
    yrs <- vapply(m$files$long_partitions, function(p) as.integer(p$year),
                  integer(1))
    expect_setequal(yrs, c(2011L, 2012L, 2019L, 2020L))
  })
})

test_that(".validate_schema accepts schema_version 4 through 7, rejects others", {
  expect_silent(uscogdata:::.validate_schema(list(schema_version = 4L)))
  expect_silent(uscogdata:::.validate_schema(list(schema_version = 5L)))
  # v6 = FIPS geography harmonization (2026-07-22): _code -> _asof rename +
  # cog_legacy_* columns (26 -> 28 cols). This package references none of the
  # renamed columns and its geography comes from the xwalk, so v6 is accepted
  # without behavioural change -- see .validate_schema()'s note.
  expect_silent(uscogdata:::.validate_schema(list(schema_version = 6L)))
  # v7 = `data_year` APPENDED as column 29 (cog_pipeline #80, 2026-08-03), the
  # most recent fiscal year contributing to a collapsed key. Appended, never
  # inserted: canonical_govid stays at position 26, so nothing this package
  # reads shifts. Verified against the real v7 corpus before widening the
  # allow-list -- cog_spending()/cog_balances() return correctly for FY2024 AND
  # for FY2012, so the new column is inert here.
  expect_silent(uscogdata:::.validate_schema(list(schema_version = 7L)))
  expect_error(
    uscogdata:::.validate_schema(list(schema_version = 3L)),
    "schema_version"
  )
  # The upper bound still has to be ENFORCED, not just moved. Without this the
  # test would no longer prove that an unknown future schema is refused, and a
  # v8 corpus with a genuinely breaking change would sail through.
  expect_error(
    uscogdata:::.validate_schema(list(schema_version = 8L)),
    "schema_version"
  )
})

test_that("cog_open succeeds against a doctored schema_version 4 corpus (dual-accept)", {
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    con <- cog_open()
    expect_true(DBI::dbIsValid(con))
    expect_equal(as.integer(cog_manifest()$schema_version), 4L)

    # Core (pre-Phase-R2) views must still register on a v4 corpus.
    views <- DBI::dbGetQuery(con,
      "SELECT table_name FROM information_schema.tables
       WHERE table_schema = 'main' AND table_type = 'VIEW'"
    )$table_name
    expect_true(all(c("spending_annotated", "revenue_annotated") %in% views))

    # Schema-v5-only harmonization views must NOT register on a v4 corpus:
    # their parquet sources don't exist there and DuckDB's read_parquet()
    # errors eagerly at CREATE VIEW time for a missing file/glob, so
    # .register_views() gates these on manifest$schema_version >= 5.
    expect_false(any(c(
      "spending_long_harmonized", "spending_annotated_harmonized",
      "harmonization_recipes", "harmonization_map", "series_breaks_pq"
    ) %in% views))
  })
})
