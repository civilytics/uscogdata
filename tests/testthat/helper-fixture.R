# tests/testthat/helper-fixture.R
skip_if_no_corpus <- function() {
  testthat::skip_if(Sys.getenv("USCOGDATA_FIXTURE_URL", "") == "" &&
                    !file.exists("~/.cache/R/uscogdata/manifest.json"),
                    "No fixture corpus available")
}
