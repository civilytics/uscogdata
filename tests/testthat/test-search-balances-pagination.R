# tests/testthat/test-search-balances-pagination.R
#
# uscogdata#57. cog_spending()/cog_revenue() gained limit/offset in #39;
# cog_gov_search() and cog_balances() did not, so every consumer of those two
# was back to materialize-then-slice -- the exact pattern that wedged the
# production API for hours on 2026-08-06.
#
# cog_gov_search() was also the one verb with no LIMIT at all, so an
# unfiltered call returns the entire 40,336-row crosswalk by accident.

# --- cog_gov_search() -------------------------------------------------------

test_that("cog_gov_search() limit returns the first page of the unpaginated result", {
  skip_if_no_corpus()
  full <- cog_gov_search(state = "WI", type = "city")
  skip_if(nrow(full) < 12L, "fixture has too few WI cities to page")

  page <- cog_gov_search(state = "WI", type = "city", limit = 5L)
  expect_equal(nrow(page), 5L)
  expect_equal(page$canonical_govid, full$canonical_govid[1:5])
})

test_that("cog_gov_search() offset skips ahead without gaps or overlap", {
  skip_if_no_corpus()
  full <- cog_gov_search(state = "WI", type = "city")
  skip_if(nrow(full) < 12L, "fixture has too few WI cities to page")

  p1 <- cog_gov_search(state = "WI", type = "city", limit = 5L)
  p2 <- cog_gov_search(state = "WI", type = "city", limit = 5L, offset = 5L)
  expect_equal(p2$canonical_govid, full$canonical_govid[6:10])
  expect_length(intersect(p1$canonical_govid, p2$canonical_govid), 0L)
})

test_that("walking every page reconstructs the unpaginated search exactly", {
  skip_if_no_corpus()
  full <- cog_gov_search(state = "WI", type = "city")
  n <- nrow(full)
  limit <- 7L
  pages <- list()
  offset <- 0L
  repeat {
    p <- cog_gov_search(state = "WI", type = "city", limit = limit, offset = offset)
    if (nrow(p) == 0L) break
    pages[[length(pages) + 1L]] <- p
    offset <- offset + limit
    if (offset > n + limit) stop("test runaway: paging did not terminate")
  }
  walked <- dplyr::bind_rows(pages)
  expect_equal(nrow(walked), n)
  expect_equal(walked$canonical_govid, full$canonical_govid)
})

test_that("cog_gov_search() total_rows reports the full unpaginated count", {
  skip_if_no_corpus()
  full <- cog_gov_search(state = "WI", type = "city")
  page <- cog_gov_search(state = "WI", type = "city", limit = 3L)
  expect_equal(attr(page, "total_rows"), nrow(full))
})

test_that("cog_gov_search() offset past the end reports the true total, not zero", {
  skip_if_no_corpus()
  full <- cog_gov_search(state = "WI", type = "city")
  # No row survives to carry COUNT(*) OVER(), so this is the branch that has
  # to fall back to a second count rather than reporting 0 rows out of 0.
  page <- cog_gov_search(state = "WI", type = "city",
                         limit = 5L, offset = nrow(full) + 50L)
  expect_equal(nrow(page), 0L)
  expect_equal(attr(page, "total_rows"), nrow(full))
})

test_that("cog_gov_search() bounds an otherwise-unfiltered crosswalk sweep", {
  skip_if_no_corpus()
  # The reason this verb needed a limit most: with no filter it returns the
  # whole crosswalk.
  page <- cog_gov_search(limit = 10L)
  expect_equal(nrow(page), 10L)
  expect_gt(attr(page, "total_rows"), 10L)
})

test_that("cog_gov_search() orders by a total order, not population alone", {
  skip_if_no_corpus()
  # population_acs is not unique -- NA in particular repeats across many rows
  # -- so paging on it alone can duplicate a row on one page and drop it from
  # the next. The tiebreaker is what makes the sequence reproducible.
  full <- cog_gov_search(state = "WI")
  skip_if(nrow(full) < 5L, "fixture has too few WI governments")
  expect_equal(cog_gov_search(state = "WI")$canonical_govid,
               full$canonical_govid)

  ties <- full[is.na(full$population_acs), ]
  skip_if(nrow(ties) < 2L, "no tied rows in the fixture to order")
  expect_false(is.unsorted(ties$canonical_govid))
})

test_that("cog_gov_search() refuses pagination in basket mode", {
  skip_if_no_corpus()
  expect_error(
    cog_gov_search(name = c("MADISON CITY", "MILWAUKEE CITY"),
                   state = c("WI", "WI"), limit = 1L),
    class = "uscogdata_basket_pagination_conflict"
  )
})

test_that("cog_gov_search() rejects a malformed limit or offset", {
  skip_if_no_corpus()
  expect_error(cog_gov_search(state = "WI", limit = -1L),
               class = "uscogdata_invalid_pagination")
  expect_error(cog_gov_search(state = "WI", limit = 5L, offset = -1L),
               class = "uscogdata_invalid_pagination")
})

# --- cog_balances() ---------------------------------------------------------

test_that("cog_balances() limit/offset walk the unpaginated result exactly", {
  skip_if_no_corpus()
  full <- cog_balances(years = 2019:2020, state = "WI", type = "city")
  skip_if(nrow(full) < 6L, "fixture has too few WI city balance rows to page")

  key <- c("year", "canonical_govid", "balance_subtype", "amt_nominal")
  p1 <- cog_balances(years = 2019:2020, state = "WI", type = "city", limit = 3L)
  p2 <- cog_balances(years = 2019:2020, state = "WI", type = "city",
                     limit = 3L, offset = 3L)

  expect_equal(nrow(p1), 3L)
  expect_equal(p1[key], full[1:3, key], ignore_attr = TRUE)
  expect_equal(p2[key], full[4:6, key], ignore_attr = TRUE)
  # The window-function column is an implementation detail and must not reach
  # the caller's data frame.
  expect_false("pagination_total_rows" %in% names(p1))
})

test_that("cog_balances() total_rows reports the full unpaginated count", {
  skip_if_no_corpus()
  full <- cog_balances(years = 2019:2020, state = "WI", type = "city")
  page <- cog_balances(years = 2019:2020, state = "WI", type = "city", limit = 2L)
  expect_equal(attr(page, "total_rows"), nrow(full))
})

test_that("cog_balances() offset past the end reports the true total", {
  skip_if_no_corpus()
  full <- cog_balances(years = 2019:2020, state = "WI", type = "city")
  page <- cog_balances(years = 2019:2020, state = "WI", type = "city",
                       limit = 5L, offset = nrow(full) + 50L)
  expect_equal(nrow(page), 0L)
  expect_equal(attr(page, "total_rows"), nrow(full))
})

test_that("cog_balances() refuses pagination alongside a recipe", {
  skip_if_no_corpus()
  expect_error(
    cog_balances(years = 2011, state = "WI", type = "city",
                 recipe = "cash_securities_z77_wide", limit = 5L),
    class = "uscogdata_recipe_pagination_conflict"
  )
})

test_that("cog_balances() rejects a malformed limit or offset", {
  skip_if_no_corpus()
  expect_error(cog_balances(years = 2019, state = "WI", type = "city", limit = -1L),
               class = "uscogdata_invalid_pagination")
  expect_error(cog_balances(years = 2019, state = "WI", type = "city",
                            limit = 5L, offset = -1L),
               class = "uscogdata_invalid_pagination")
})

# --- Unchanged without the arguments ----------------------------------------

test_that("both verbs are unchanged when limit is not supplied", {
  skip_if_no_corpus()
  # The adoption contract for cog-api: NULL default, so a formals() probe can
  # feature-detect without any call site changing behaviour.
  s <- cog_gov_search(state = "WI", type = "city")
  b <- cog_balances(years = 2019, state = "WI", type = "city")
  expect_null(attr(s, "total_rows"))
  expect_null(attr(b, "total_rows"))
  expect_true(all(c("limit", "offset") %in% names(formals(cog_gov_search))))
  expect_true(all(c("limit", "offset") %in% names(formals(cog_balances))))
})
