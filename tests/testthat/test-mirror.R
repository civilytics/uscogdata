test_that("cog_mirror copies manifest + metadata files", {
  skip_if_no_corpus()
  tmp <- tempfile("uscogmirror_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  r <- cog_mirror(tmp, include = "metadata", progress = FALSE)
  expect_s3_class(r, "tbl_df")
  expect_true(file.exists(file.path(tmp, "manifest.json")))
  expect_true(file.exists(file.path(tmp, "data/canonical_fips_xwalk.parquet")))
  expect_true(file.exists(file.path(tmp, "data/summary_categories.parquet")))
  expect_true(all(r$status == "downloaded"))
  expect_true(all(c("path", "sha256", "size_bytes", "status") %in% names(r)))
})

test_that("cog_mirror is idempotent when SHA matches (status = 'cached')", {
  skip_if_no_corpus()
  tmp <- tempfile("uscogmirror_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  cog_mirror(tmp, include = "metadata", progress = FALSE)
  r2 <- cog_mirror(tmp, include = "metadata", progress = FALSE)
  expect_true(all(r2$status == "cached"))
})

test_that("cog_mirror overwrite = TRUE re-copies even when SHA matches", {
  skip_if_no_corpus()
  tmp <- tempfile("uscogmirror_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  cog_mirror(tmp, include = "metadata", progress = FALSE)
  r3 <- cog_mirror(tmp, include = "metadata", progress = FALSE, overwrite = TRUE)
  expect_true(all(r3$status == "downloaded"))
})

test_that("cog_mirror verifies sha256 against manifest", {
  skip_if_no_corpus()
  tmp <- tempfile("uscogmirror_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  r <- cog_mirror(tmp, include = "metadata", progress = FALSE)
  for (i in seq_len(nrow(r))) {
    got <- digest::digest(file.path(tmp, r$path[i]),
                          algo = "sha256", file = TRUE)
    expect_equal(got, r$sha256[i])
  }
})

test_that("cog_mirror reads back via a fresh session against the mirror", {
  skip_if_no_corpus()
  tmp <- tempfile("uscogmirror_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  cog_mirror(tmp, include = c("long", "metadata"), progress = FALSE)

  # Re-open against the local mirror and run a query.
  old_url <- getOption("uscogdata.url")
  on.exit({
    cog_close()
    options(uscogdata.url = old_url)
  }, add = TRUE)
  cog_close()
  options(uscogdata.url = paste0(normalizePath(tmp), "/"))

  r <- cog_spending("121011212191", 2020L, "Corrections")
  expect_gt(nrow(r), 0L)
  expect_equal(unique(r$canonical_govid), "121011212191")
})
