# tests/testthat/setup.R
# Priority: bundled fixture > USCOGDATA_FIXTURE_URL env var > whatever is already set.
local({
  p <- system.file("extdata/fixture_corpus", package = "uscogdata")
  if (nzchar(p) && file.exists(file.path(p, "manifest.json"))) {
    Sys.setenv(USCOGDATA_URL = paste0(p, "/"))
  } else if (nzchar(Sys.getenv("USCOGDATA_FIXTURE_URL", ""))) {
    Sys.setenv(USCOGDATA_URL = Sys.getenv("USCOGDATA_FIXTURE_URL"))
  }
})

# Reset DuckDB session between test files so each file starts clean.
withr::defer(uscogdata:::cog_close(), teardown_env())
