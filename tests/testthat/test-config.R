test_that(".cfg resolves defaults, options, and env vars in priority order", {
  withr::with_options(list(uscogdata.manifest_ttl_secs = NULL), {
    withr::with_envvar(c(USCOGDATA_MANIFEST_TTL_SECS = NA), {
      expect_equal(uscogdata:::.cfg("manifest_ttl_secs"), 3600L)
    })
  })

  withr::with_options(list(uscogdata.url = "https://opt.example/"), {
    withr::with_envvar(c(USCOGDATA_URL = NA), {
      expect_equal(uscogdata:::.cfg("url"), "https://opt.example/")
    })
  })

  withr::with_envvar(c(USCOGDATA_URL = "https://env.example/"), {
    withr::with_options(list(uscogdata.url = "https://opt.example/"), {
      expect_equal(uscogdata:::.cfg("url"), "https://env.example/")
    })
  })
})

test_that(".resolve_cache_dir falls back to R_user_dir", {
  withr::with_envvar(c(USCOGDATA_CACHE_DIR = NA), {
    withr::with_options(list(uscogdata.cache_dir = NULL), {
      expect_equal(uscogdata:::.resolve_cache_dir(),
                   tools::R_user_dir("uscogdata", "cache"))
    })
  })
})

# ---------------------------------------------------------------------------
# Trailing-slash normalization (uscogdata #3 follow-up).
#
# EVERY consumer builds paths by concatenation: paste0(url, "manifest.json")
# (manifest.R), paste0(url, e$path) (mirror.R), and the parquet glob in
# views.R. mirror.R:104 even comments 'url ends in "/"' -- an assumption the
# package documents and relies on but never enforced.
#
# A URL missing its trailing slash therefore fails SILENTLY and confusingly:
#   HTTPS -> ".../downloadmanifest.json" -> the host answers with an HTML 404
#            page -> the jsonlite lexical error that issue #3 reported;
#   local -> ".../corpusdata/long/**/*.parquet" -> DuckDB "No files found".
# Neither message points at the real cause. Normalize once, at resolution.
# ---------------------------------------------------------------------------

test_that(".resolve_url appends a missing trailing slash", {
  withr::local_envvar(USCOGDATA_URL = "https://example.org/s/TOKEN/download")
  expect_equal(.resolve_url(), "https://example.org/s/TOKEN/download/")
})

test_that(".resolve_url leaves an existing trailing slash alone", {
  withr::local_envvar(USCOGDATA_URL = "https://example.org/s/TOKEN/download/")
  expect_equal(.resolve_url(), "https://example.org/s/TOKEN/download/")
})

test_that(".resolve_url normalizes a local path without a trailing slash", {
  withr::local_envvar(USCOGDATA_URL = "/tmp/corpus")
  expect_equal(.resolve_url(), "/tmp/corpus/")
})

test_that(".resolve_url does not invent a slash for an empty setting", {
  # An unset/empty URL must stay empty so the "not configured" guard in
  # manifest.R still fires, rather than degrading into a bare "/" root.
  withr::local_envvar(USCOGDATA_URL = "")
  withr::local_options(uscogdata.url = "")
  expect_equal(.resolve_url(), "")
})

test_that("the default corpus URL is real, not a placeholder", {
  # setup.R points USCOGDATA_URL at the bundled fixture for the whole suite,
  # so both the env var and the option have to be cleared to see the default.
  withr::local_envvar(USCOGDATA_URL = NA)
  withr::local_options(uscogdata.url = NULL)
  url <- .resolve_url()
  expect_false(grepl("REPLACE_WITH", url, fixed = TRUE))
  expect_match(url, "^https://")
  expect_match(url, "/$")
})

test_that("an explicitly-set sentinel URL still aborts", {
  # The guard must survive the default change: a user who half-edited a
  # copied config still gets the actionable error.
  withr::local_envvar(
    USCOGDATA_URL = "https://other.example/s/REPLACE_WITH_SHARE_TOKEN/x/"
  )
  expect_error(
    .check_url_configured(.resolve_url()),
    class = "uscogdata_url_not_configured"
  )
})
