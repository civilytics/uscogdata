test_that("cpi_annual internal data is available with expected shape", {
  cpi <- uscogdata:::.cpi_table()
  expect_true(is.data.frame(cpi))
  expect_named(cpi, c("year", "cpi"))
  expect_true(nrow(cpi) > 70L)
  expect_true(all(c(2000L, 2010L, 2021L) %in% cpi$year))
})

test_that(".inflate matches a known anchor: 2000 in 2021$ ≈ 1.57x nominal", {
  # FRED CPIAUCSL annual: 2000=172.19, 2021=270.97 → ratio ≈ 1.574
  result <- uscogdata:::.inflate(100, from_year = 2000, to_year = 2021)
  expect_equal(result, 157.4, tolerance = 0.5)
})

test_that(".inflate is vectorized over from_year", {
  result <- uscogdata:::.inflate(
    amt       = c(100, 100, 100),
    from_year = c(2000, 2010, 2021),
    to_year   = 2021
  )
  expect_length(result, 3L)
  expect_equal(result[3], 100, tolerance = 1e-6)  # same year → identity
  expect_gt(result[1], 150)  # 2000 inflated to 2021 ≈ 157
  expect_lt(result[2], 130)  # 2010 inflated to 2021 ≈ 124
  expect_gt(result[2], 115)
})

test_that(".inflate errors on unknown from_year or to_year", {
  expect_error(
    uscogdata:::.inflate(100, from_year = 1900, to_year = 2021),
    "CPI unavailable for from_year"
  )
  expect_error(
    uscogdata:::.inflate(100, from_year = 2000, to_year = 2200),
    "CPI unavailable for to_year"
  )
})

test_that(".inflate preserves NA amounts", {
  result <- uscogdata:::.inflate(c(100, NA, 200), from_year = 2000, to_year = 2021)
  expect_true(is.na(result[2]))
  expect_false(any(is.na(result[c(1, 3)])))
})
