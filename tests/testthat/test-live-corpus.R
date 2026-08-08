# Network-gated. Set USCOGDATA_LIVE_TEST=true to run.
#
# This file exists because the defect fixed for 0.3.0 -- no remote corpus was
# readable at all, because DuckDB cannot expand a glob over generic HTTP --
# survived precisely because every other test path used a LOCAL corpus (the
# bundled fixture), and so did the API in production (a host mount). Nothing
# ever exercised the package the way a new user does.
skip_live <- function() {
  testthat::skip_if_not(
    identical(tolower(Sys.getenv("USCOGDATA_LIVE_TEST", "")), "true"),
    "live-corpus test: set USCOGDATA_LIVE_TEST=true to run"
  )
}

# The suite's setup.R pins USCOGDATA_URL to the bundled fixture, so reaching
# the default requires clearing both the env var and the option.
with_default_corpus <- function(code) {
  withr::local_envvar(
    USCOGDATA_URL = NA, USCOGDATA_FIXTURE_URL = NA,
    .local_envir = parent.frame()
  )
  withr::local_options(uscogdata.url = NULL, .local_envir = parent.frame())
  cog_close()
  withr::defer(cog_close(), envir = parent.frame())
  force(code)
}

test_that("the package reads the public corpus with no configuration at all", {
  skip_live()
  with_default_corpus({
    g <- cog_gov_search(name = "Madison", state = "WI", type = 2)
    expect_gt(nrow(g), 0)

    s <- cog_spending(g$canonical_govid[1], years = 2022)
    expect_gt(nrow(s), 0)
    expect_true(all(c("amt_nominal", "year", "category") %in% names(s)))

    # Amounts are full dollars, already x1000. A city's annual spending is
    # millions, not thousands -- this catches a regression that dropped or
    # doubled the conversion.
    expect_gt(sum(s$amt_nominal, na.rm = TRUE), 1e6)

    p <- attr(s, "provenance")
    expect_true(isTRUE(p$transformations$units_conversion$applied))
    expect_equal(p$transformations$units_conversion$multiplier, 1000)
  })
})

test_that("a multi-decade query reads across many partitions", {
  skip_live()
  with_default_corpus({
    g <- cog_gov_search(name = "Madison", state = "WI", type = 2)
    # `years` is required on cog_spending() -- there is no full-history
    # default at the reader level (the API's /profile route supplies one).
    s <- cog_spending(g$canonical_govid[1], years = 2000:2022)
    # Enumeration builds one read_parquet() path per requested partition. If
    # the list were truncated, or silently collapsed to a single file, the
    # returned span is what catches it.
    expect_gt(diff(range(s$year)), 10)
    expect_gt(length(unique(s$year)), 5)
  })
})
