# tests/testthat/test-fiscal-period.R
#
# uscogdata#77: fiscal_year_end, period_start/period_end on the verbs, and the
# survey-year helpers. Expected values come from the bundled fixture (FY2011,
# FY2012, FY2019, FY2020), where these governments' fiscal_year_end is:
#   Georgia state 630, Alabama state 930, Texas state 831, New York state 331,
#   Washington DC (type 2) 930, Broward County FL 930.

ga_state <- "130000226087"
al_state <- "010000226085"
tx_state <- "480000227541"
ny_state <- "360000227535"
dc       <- "112001124214"
broward  <- "121011212191"

fiscal_cols <- c("fiscal_year_end", "period_start", "period_end")

# --- the rule itself (no corpus) ----------------------------------------------

test_that("local governments follow the July 1 - June 30 survey-year rule", {
  p <- uscogdata:::.survey_period(
    year = rep(2017L, 4), fiscal_year_end = c(630L, 930L, 1231L, 701L),
    gov_type = rep(2L, 4), canonical_govid = rep("x", 4))
  expect_equal(p$period_start,
               as.Date(c("2016-07-01", "2015-10-01", "2016-01-01", "2015-07-02")))
  expect_equal(p$period_end,
               as.Date(c("2017-06-30", "2016-09-30", "2016-12-31", "2016-07-01")))
})

test_that("state governments cover the fiscal year ending in the survey year", {
  p <- uscogdata:::.survey_period(
    year = rep(2017L, 4), fiscal_year_end = c(930L, 831L, 331L, 630L),
    gov_type = rep(0L, 4), canonical_govid = rep("x", 4))
  expect_equal(p$period_start,
               as.Date(c("2016-10-01", "2016-09-01", "2016-04-01", "2016-07-01")))
  expect_equal(p$period_end,
               as.Date(c("2017-09-30", "2017-08-31", "2017-03-31", "2017-06-30")))
})

test_that("the District of Columbia follows the state-government rule", {
  dc_p <- uscogdata:::.survey_period(2017L, 930L, 2L, dc)
  city <- uscogdata:::.survey_period(2017L, 930L, 2L, "999999999999")
  expect_equal(c(dc_p$period_start, dc_p$period_end),
               as.Date(c("2016-10-01", "2017-09-30")))
  expect_equal(c(city$period_start, city$period_end),
               as.Date(c("2015-10-01", "2016-09-30")))
})

test_that("February year ends respect leap years", {
  p <- uscogdata:::.survey_period(
    year = c(2017L, 2017L, 2016L), fiscal_year_end = c(228L, 229L, 229L),
    gov_type = rep(1L, 3), canonical_govid = rep("x", 3))
  expect_equal(p$period_end,
               as.Date(c("2017-02-28", "2017-02-28", "2016-02-29")))
  expect_equal(p$period_start,
               as.Date(c("2016-02-29", "2016-03-01", "2015-03-01")))
})

test_that("missing, zero and impossible fiscal_year_end values give NA periods", {
  p <- uscogdata:::.survey_period(
    year = rep(2017L, 5), fiscal_year_end = c(NA, 0L, 1331L, 1232L, 231L),
    gov_type = rep(1L, 5), canonical_govid = rep("x", 5))
  expect_true(all(is.na(p$period_start)))
  expect_true(all(is.na(p$period_end)))
})

test_that("a government-year whose rows disagree gets no fiscal_year_end", {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE long AS SELECT * FROM (VALUES
      ('a', 2020, 1, 630), ('a', 2020, 1, 630),
      ('b', 2020, 2, 630), ('b', 2020, 2, 1231),
      ('c', 2020, 3, NULL), ('c', 2020, 3, 930))
    AS t(canonical_govid, year, type, fiscal_year_end)")
  fy <- uscogdata:::.fiscal_year_lookup(con, c("a", "b", "c"), 2020L)
  fy <- fy[order(fy$canonical_govid), ]
  expect_equal(fy$fiscal_year_end, c(630L, NA, 930L))
})

# --- the verbs -----------------------------------------------------------------

test_that("fiscal_period defaults to FALSE and changes nothing when unset", {
  skip_if_no_corpus()
  for (f in list(cog_spending, cog_revenue, cog_balances)) {
    expect_false(formals(f)$fiscal_period)
  }
  s0 <- cog_spending(c(ga_state, broward), 2020, category = "Highways")
  s1 <- cog_spending(c(ga_state, broward), 2020, category = "Highways",
                     fiscal_period = FALSE)
  expect_false(any(fiscal_cols %in% names(s0)))
  expect_identical(names(s0), names(s1))
  expect_null(attr(s0, "provenance")$transformations$fiscal_period)

  b0 <- suppressMessages(cog_balances(al_state, 2020))
  expect_false(any(fiscal_cols %in% names(b0)))
  expect_null(attr(b0, "provenance")$transformations$fiscal_period)
})

test_that("cog_spending(fiscal_period = TRUE) adds per-row periods at the end", {
  skip_if_no_corpus()
  plain <- cog_spending(c(ga_state, al_state, broward), 2019:2020,
                        category = "Highways")
  r <- cog_spending(c(ga_state, al_state, broward), 2019:2020,
                    category = "Highways", fiscal_period = TRUE)

  expect_identical(names(r), c(names(plain), fiscal_cols))
  expect_equal(r[names(plain)], plain, ignore_attr = TRUE)
  expect_type(r$fiscal_year_end, "integer")
  expect_s3_class(r$period_start, "Date")
  expect_s3_class(r$period_end, "Date")

  one <- function(id, y) {
    unique(r[r$canonical_govid == id & r$year == y, fiscal_cols])
  }
  expect_equal(one(ga_state, 2020)$period_start, as.Date("2019-07-01"))
  expect_equal(one(ga_state, 2020)$period_end, as.Date("2020-06-30"))
  expect_equal(one(al_state, 2020)$fiscal_year_end, 930L)
  expect_equal(one(al_state, 2020)$period_end, as.Date("2020-09-30"))
  expect_equal(one(broward, 2020)$fiscal_year_end, 930L)
  expect_equal(one(broward, 2020)$period_start, as.Date("2018-10-01"))
  expect_equal(one(broward, 2020)$period_end, as.Date("2019-09-30"))
  expect_equal(one(broward, 2019)$period_end, as.Date("2018-09-30"))

  fp <- attr(r, "provenance")$transformations$fiscal_period
  expect_true(fp$applied)
  expect_equal(fp$rows_without_period, 0L)
})

test_that("cog_revenue and cog_balances take fiscal_period", {
  skip_if_no_corpus()
  tx <- suppressMessages(cog_revenue(tx_state, 2019, category = "IG Federal",
                                     fiscal_period = TRUE))
  expect_gt(nrow(tx), 0L)
  expect_true(all(tx$fiscal_year_end == 831L))
  expect_true(all(tx$period_start == as.Date("2018-09-01")))
  expect_true(all(tx$period_end == as.Date("2019-08-31")))

  ny <- suppressMessages(cog_revenue(ny_state, 2020, category = "IG Federal",
                                     fiscal_period = TRUE))
  expect_true(all(ny$period_start == as.Date("2019-04-01")))
  expect_true(all(ny$period_end == as.Date("2020-03-31")))

  bal <- suppressMessages(cog_balances(al_state, 2020, fiscal_period = TRUE))
  expect_gt(nrow(bal), 0L)
  expect_identical(tail(names(bal), 3L), fiscal_cols)
  expect_true(all(bal$period_end == as.Date("2020-09-30")))
  expect_true(attr(bal, "provenance")$transformations$fiscal_period$applied)
})

test_that("fiscal_period composes with per_capita, adjust_to_year, limit and complete", {
  skip_if_no_corpus()
  r <- cog_spending(broward, 2020, per_capita = TRUE, adjust_to_year = 2020,
                    fiscal_period = TRUE, limit = 3)
  expect_equal(nrow(r), 3L)
  expect_identical(tail(names(r), 3L), fiscal_cols)
  expect_true(all(r$period_end == as.Date("2019-09-30")))
  expect_false(is.null(attr(r, "total_rows")))

  cpl <- suppressMessages(cog_spending(broward, 2020, category = "Police",
                                       complete = TRUE, fiscal_period = TRUE))
  expect_true("value_source" %in% names(cpl))
  expect_identical(tail(names(cpl), 3L), fiscal_cols)
})

test_that("fiscal_period is validated", {
  expect_error(cog_spending(ga_state, 2020, fiscal_period = NA), "fiscal_period")
  expect_error(cog_spending(ga_state, 2020, fiscal_period = "yes"), "fiscal_period")
  expect_error(cog_revenue(ga_state, 2020, fiscal_period = c(TRUE, FALSE)),
               "fiscal_period")
  expect_error(cog_balances(ga_state, 2020, fiscal_period = 1), "fiscal_period")
})

# --- cog_fiscal_periods() ---------------------------------------------------------

test_that("cog_fiscal_periods() returns the govid x years grid, NA where unknown", {
  skip_if_no_corpus()
  fp <- cog_fiscal_periods(c(ga_state, al_state, dc, broward), c(2018, 2020))
  expect_s3_class(fp, "tbl_df")
  expect_identical(names(fp), c("canonical_govid", "year", fiscal_cols))
  expect_equal(nrow(fp), 8L)
  expect_identical(fp$canonical_govid, rep(c(ga_state, al_state, dc, broward), each = 2))
  expect_identical(fp$year, rep(c(2018L, 2020L), 4))

  y20 <- fp[fp$year == 2020, ]
  expect_equal(y20$fiscal_year_end, c(630L, 930L, 930L, 930L))
  expect_equal(y20$period_start,
               as.Date(c("2019-07-01", "2019-10-01", "2019-10-01", "2018-10-01")))
  expect_equal(y20$period_end,
               as.Date(c("2020-06-30", "2020-09-30", "2020-09-30", "2019-09-30")))

  # FY2018 is not in the fixture.
  expect_true(all(is.na(fp$period_end[fp$year == 2018])))
})

test_that("cog_fiscal_periods() matches the verb columns", {
  skip_if_no_corpus()
  r <- cog_spending(c(ga_state, broward), 2019:2020, category = "Highways",
                    fiscal_period = TRUE)
  fp <- cog_fiscal_periods(c(ga_state, broward), 2019:2020)
  m <- merge(unique(as.data.frame(r[c("canonical_govid", "year", fiscal_cols)])),
             as.data.frame(fp), by = c("canonical_govid", "year"))
  expect_gt(nrow(m), 0L)
  expect_equal(m$period_start.x, m$period_start.y)
  expect_equal(m$period_end.x, m$period_end.y)
})

test_that("cog_fiscal_periods() validates its inputs", {
  expect_error(cog_fiscal_periods(years = 2020), "govid")
  expect_error(cog_fiscal_periods(ga_state), "years")
  expect_error(cog_fiscal_periods(character(0), 2020), "govid")
  expect_error(cog_fiscal_periods(ga_state, "2020"), "years")
  expect_error(cog_fiscal_periods(ga_state, c(2020, NA)), "years")
})

# --- cog_survey_year() -------------------------------------------------------------

test_that("cog_survey_year() maps a date to the survey year that covers it", {
  skip_if_no_corpus()
  s <- cog_survey_year(c(broward, al_state, ga_state), as.Date("2019-04-15"))
  expect_identical(names(s), c("canonical_govid", "date", "year", fiscal_cols))
  # Broward: FY ending 2019-09-30 is survey year 2020 (plain rule).
  # Alabama state: FY ending 2019-09-30 is survey year 2019 (state rule).
  # Georgia state: FY ending 2019-06-30 is survey year 2019.
  expect_identical(s$year, c(2020L, 2019L, 2019L))
  expect_equal(s$period_end, as.Date(c("2019-09-30", "2019-09-30", "2019-06-30")))
})

test_that("cog_survey_year() respects period boundaries and returns NA when it cannot tell", {
  skip_if_no_corpus()
  s <- cog_survey_year(broward, c("2018-10-01", "2019-09-30", "2018-09-30",
                                  NA, "2019-12-01"))
  # 2019-12-01 falls in survey year 2021, which the fixture does not carry.
  expect_identical(s$year, c(2020L, 2020L, 2019L, NA, NA))
  expect_s3_class(s$date, "Date")
})

test_that("cog_survey_year() and cog_fiscal_periods() agree", {
  skip_if_no_corpus()
  fp <- cog_fiscal_periods(c(ga_state, al_state, broward), 2020)
  s <- cog_survey_year(fp$canonical_govid, fp$period_start)
  e <- cog_survey_year(fp$canonical_govid, fp$period_end)
  expect_identical(s$year, fp$year)
  expect_identical(e$year, fp$year)
})

test_that("cog_survey_year() validates its inputs", {
  expect_error(cog_survey_year(date = "2020-01-01"), "govid")
  expect_error(cog_survey_year(ga_state), "date")
  expect_error(cog_survey_year(c(ga_state, broward), c("2020-01-01", "2020-02-01",
                                                       "2020-03-01")),
               "same length")
  expect_error(cog_survey_year(ga_state, "2020-13-01"), "not dates")
  expect_error(cog_survey_year(ga_state, 20200101), "Date")
  expect_error(cog_survey_year(ga_state, as.Date(character(0))), "empty")
})

test_that("new helpers are exported", {
  expect_true(all(c("cog_fiscal_periods", "cog_survey_year") %in%
                    getNamespaceExports("uscogdata")))
})
