# tests/testthat/helper-fixture.R

# Returns the path to the bundled fixture corpus (trailing slash for DuckDB globs).
fixture_corpus_path <- function() {
  p <- system.file("extdata/fixture_corpus", package = "uscogdata")
  if (nzchar(p)) paste0(p, "/") else ""
}

# Skip a test if no corpus is reachable (bundled fixture or explicit remote URL).
skip_if_no_corpus <- function() {
  p <- fixture_corpus_path()
  has_fixture <- nzchar(p) && file.exists(sub("/$", "/manifest.json", p))
  has_remote  <- nzchar(Sys.getenv("USCOGDATA_FIXTURE_URL", ""))
  testthat::skip_if(!has_fixture && !has_remote, "No fixture corpus available")
}

# Run a block against the fixture corpus with a clean session.
# Restores the previous URL and closes the DuckDB connection when done.
with_fixture_corpus <- function(code) {
  old_url <- Sys.getenv("USCOGDATA_URL", unset = NA)
  uscogdata:::cog_close()
  Sys.setenv(USCOGDATA_URL = fixture_corpus_path())
  on.exit({
    uscogdata:::cog_close()
    if (is.na(old_url)) Sys.unsetenv("USCOGDATA_URL") else Sys.setenv(USCOGDATA_URL = old_url)
  }, add = TRUE)
  force(code)
}

# Copy the bundled fixture to a temp dir with manifest.json's schema_version
# patched to `version`, then run `code` against it with a clean session
# (mirrors with_fixture_corpus()). Used to exercise the v4/v5 dual-accept
# path without a second physical fixture tree: a real v4 corpus has no
# harmonization_map/harmonization_recipes/series_breaks parquet files, but
# .register_views() only *reads* those when schema_version >= 5 (see
# R/views.R), so a doctored copy of the (v5) bundled fixture with the
# manifest's schema_version knocked down to 4 is a faithful stand-in.
with_doctored_schema_version <- function(version, code) {
  src <- fixture_corpus_path()
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  file.copy(list.files(src, full.names = TRUE), tmp, recursive = TRUE)

  manifest_path <- file.path(tmp, "manifest.json")
  m <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
  m$schema_version <- as.integer(version)
  writeLines(
    jsonlite::toJSON(m, auto_unbox = TRUE, pretty = TRUE, null = "null"),
    manifest_path
  )

  old_url <- Sys.getenv("USCOGDATA_URL", unset = NA)
  uscogdata:::cog_close()
  Sys.setenv(USCOGDATA_URL = paste0(tmp, "/"))
  on.exit({
    uscogdata:::cog_close()
    if (is.na(old_url)) Sys.unsetenv("USCOGDATA_URL") else Sys.setenv(USCOGDATA_URL = old_url)
  }, add = TRUE)
  force(code)
}
