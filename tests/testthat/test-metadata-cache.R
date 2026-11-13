# tests/testthat/test-metadata-cache.R
#
# uscogdata#64. On the remote path the ten metadata tables (about 3 MB) were
# read over HTTP every session. Kept in the cache directory and checked
# against the manifest's sha256, they cut session open from 1.7 s to 0.4 s
# against the public corpus (2026-11-12, one run per arm).
#
# The fixture is local, and a local corpus is never cached. These tests treat
# the fixture as if it were remote by handing .cache_metadata_tables() a
# fetch function that copies from it, so they run offline.

fake_remote <- "https://example.invalid/corpus/"

# A fetch that serves the fixture's bytes for the fake remote URL, and counts
# its calls.
counting_fetch <- function() {
  env <- new.env(); env$n <- 0L
  env$fetch <- function(src, dest) {
    env$n <- env$n + 1L
    rel <- sub(fake_remote, "", src, fixed = TRUE)
    stopifnot(file.copy(file.path(fixture_corpus_path(), rel), dest,
                        overwrite = TRUE))
  }
  env
}

fixture_manifest <- function() {
  jsonlite::fromJSON(file.path(fixture_corpus_path(), "manifest.json"),
                     simplifyVector = FALSE)
}

test_that("a local corpus is read in place, never cached (#64)", {
  skip_if_no_corpus()
  cd <- withr::local_tempdir()
  url <- paste0(fixture_corpus_path(), "/")
  expect_identical(.cache_metadata_tables(url, fixture_manifest(), cd), url)
  expect_false(dir.exists(file.path(cd, "corpus")))
})

test_that("remote metadata tables are cached and verified (#64)", {
  skip_if_no_corpus()
  cd <- withr::local_tempdir()
  m <- fixture_manifest()
  f <- counting_fetch()
  base <- .cache_metadata_tables(fake_remote, m, cd, fetch = f$fetch)
  expect_false(identical(base, fake_remote))
  expect_match(base, "/$")
  expect_equal(f$n, length(m$files$metadata))
  for (e in m$files$metadata) {
    p <- file.path(cd, "corpus", e$path)
    expect_true(file.exists(p), info = e$path)
    expect_equal(digest::digest(p, algo = "sha256", file = TRUE), e$sha256)
  }

  # Second session: nothing fetched.
  expect_identical(.cache_metadata_tables(fake_remote, m, cd, fetch = f$fetch),
                   base)
  expect_equal(f$n, length(m$files$metadata))
})

test_that("a cached file that no longer matches the manifest is fetched again (#64)", {
  skip_if_no_corpus()
  cd <- withr::local_tempdir()
  m <- fixture_manifest()
  f <- counting_fetch()
  .cache_metadata_tables(fake_remote, m, cd, fetch = f$fetch)
  writeLines("stale", file.path(cd, "corpus", m$files$metadata[[1]]$path))
  .cache_metadata_tables(fake_remote, m, cd, fetch = f$fetch)
  expect_equal(f$n, length(m$files$metadata) + 1L)
  p <- file.path(cd, "corpus", m$files$metadata[[1]]$path)
  expect_equal(digest::digest(p, algo = "sha256", file = TRUE),
               m$files$metadata[[1]]$sha256)
})

test_that("a download that fails its sha256 check falls back to remote (#64)", {
  skip_if_no_corpus()
  cd <- withr::local_tempdir()
  m <- fixture_manifest()
  bad_fetch <- function(src, dest) writeLines("not parquet", dest)
  expect_message(
    base <- .cache_metadata_tables(fake_remote, m, cd, fetch = bad_fetch),
    "sha256"
  )
  expect_identical(base, fake_remote)
  # Nothing unverified is left where a later session would find it.
  left <- list.files(file.path(cd, "corpus"), recursive = TRUE)
  expect_length(left, 0L)
})

test_that("a failed download falls back to remote (#64)", {
  skip_if_no_corpus()
  cd <- withr::local_tempdir()
  err_fetch <- function(src, dest) stop("HTTP 429 Too Many Requests")
  expect_message(
    base <- .cache_metadata_tables(fake_remote, fixture_manifest(), cd,
                                   fetch = err_fetch),
    "429"
  )
  expect_identical(base, fake_remote)
})

test_that("a manifest entry without a sha256 disables the cache (#64)", {
  skip_if_no_corpus()
  cd <- withr::local_tempdir()
  m <- fixture_manifest()
  m$files$metadata[[1]]$sha256 <- NULL
  f <- counting_fetch()
  expect_identical(.cache_metadata_tables(fake_remote, m, cd, fetch = f$fetch),
                   fake_remote)
  expect_equal(f$n, 0L)
})

test_that("views read metadata from the cache and partitions from the corpus (#64)", {
  skip_if_no_corpus()
  cd <- withr::local_tempdir()
  m <- fixture_manifest()
  meta <- .cache_metadata_tables(fake_remote, m, cd,
                                 fetch = counting_fetch()$fetch)
  url <- paste0(fixture_corpus_path(), "/")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  .register_views(con, url, m, meta_url = meta)

  sql_of <- function(view) DBI::dbGetQuery(con, sprintf(
    "SELECT sql FROM duckdb_views() WHERE view_name = '%s'", view))$sql
  expect_match(sql_of("summary_categories"),
               file.path(normalizePath(cd, winslash = "/"), "corpus"),
               fixed = TRUE)
  expect_match(sql_of("long"), fixture_corpus_path(), fixed = TRUE)
  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM spending_long")$n
  expect_gt(n, 0)
})
