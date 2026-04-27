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
