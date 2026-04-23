# tests/testthat/setup.R
# Point tests at a fixture corpus URL if provided.
if (Sys.getenv("USCOGDATA_FIXTURE_URL", "") != "") {
  options(uscogdata.url = Sys.getenv("USCOGDATA_FIXTURE_URL"))
}
