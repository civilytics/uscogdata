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

test_that("DESCRIPTION carries release metadata", {
  skip_if_no_source_tree("DESCRIPTION")
  d <- read.dcf(source_tree_path("DESCRIPTION"))
  fields <- colnames(d)

  expect_true(all(c("URL", "BugReports") %in% fields))
  expect_match(d[1, "Authors@R"], "Knowles", fixed = TRUE)
  expect_match(d[1, "Authors@R"], "0000-0003-0005-9478", fixed = TRUE)
  expect_match(d[1, "Authors@R"], "Civilytics Consulting LLC", fixed = TRUE)

  # The gate in .validate_schema() accepts up to 7 and the published corpus
  # IS 7; DESCRIPTION must not claim otherwise.
  expect_equal(as.integer(d[1, "MaxCorpusSchema"]), 7L)

  # Authors@R must actually parse -- a malformed person() call is only
  # caught at citation()/build time otherwise.
  people <- eval(parse(text = d[1, "Authors@R"]))
  expect_s3_class(people, "person")
  expect_true("cre" %in% unlist(lapply(people, function(p) p$role)))
})

test_that("LICENSE and LICENSE.md name the same copyright holder", {
  skip_if_no_source_tree("LICENSE", "LICENSE.md")
  holder <- sub("^COPYRIGHT HOLDER:\\s*", "",
                grep("^COPYRIGHT HOLDER:", readLines(source_tree_path("LICENSE"),
                                                     warn = FALSE), value = TRUE))
  full <- paste(readLines(source_tree_path("LICENSE.md"), warn = FALSE), collapse = "\n")

  expect_equal(holder, "Civilytics Consulting LLC")
  expect_match(full, holder, fixed = TRUE)
  # usethis::use_mit_license() writes LICENSE.md but leaves an existing
  # LICENSE alone, which is how the two came to disagree in the first place.
  expect_match(full, "MIT License", fixed = TRUE)
})

test_that("vignettes are not excluded from the build", {
  skip_if_no_source_tree(".Rbuildignore")
  ignore <- readLines(source_tree_path(".Rbuildignore"), warn = FALSE)
  expect_false(any(grepl("^\\^vignettes\\$$", ignore)))
  # The fixture is what lets R CMD check run offline with no credentials on
  # r-universe and GitHub Actions. It must never be excluded.
  expect_false(any(grepl("fixture_corpus", ignore, fixed = TRUE)))
})

test_that("_pkgdown.yml indexes every exported topic", {
  skip_if_no_source_tree("_pkgdown.yml", "NAMESPACE")
  exports <- grep("^export\\(", readLines(source_tree_path("NAMESPACE"), warn = FALSE),
                  value = TRUE)
  exports <- sub("^export\\((.*)\\)$", "\\1", exports)
  yml <- paste(readLines(source_tree_path("_pkgdown.yml"), warn = FALSE), collapse = "\n")
  missing <- exports[!vapply(exports,
                             function(e) grepl(paste0("\\b", e, "\\b"), yml),
                             logical(1))]
  # pkgdown errors on topics missing from the index, so an unlisted export
  # means the docs site does not build at all.
  expect_equal(missing, character(0))
})
