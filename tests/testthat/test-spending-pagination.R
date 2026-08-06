# cog-api's paginate() used to slice an already-fully-materialized result:
# every page of a deep sweep re-ran the whole query and re-listified every
# row, just to keep 1000 and discard the rest. For a 193,105-row fleet-wide
# query walked 194 pages deep, that repeated the full cost 194 times and
# wedged the production server for hours (2026-08-06 incident). limit/offset
# here push the slice into the SQL itself, so a page costs O(limit), not
# O(full result).

test_that("limit without offset returns the first page, matching the unpaginated head", {
  skip_if_no_corpus()
  full <- cog_spending("121011212191", years = 2019:2020, category = NULL)
  page <- cog_spending("121011212191", years = 2019:2020, category = NULL,
                       limit = 10L)
  expect_equal(nrow(page), 10L)
  expect_equal(page[c("year", "canonical_govid", "spend_subtype", "category")],
              full[1:10, c("year", "canonical_govid", "spend_subtype", "category")],
              ignore_attr = TRUE)
})

test_that("offset skips ahead without gaps or overlap", {
  skip_if_no_corpus()
  full <- cog_spending("121011212191", years = 2019:2020, category = NULL)
  page2 <- cog_spending("121011212191", years = 2019:2020, category = NULL,
                        limit = 10L, offset = 10L)
  expect_equal(nrow(page2), 10L)
  expect_equal(page2[c("year", "canonical_govid", "spend_subtype", "category")],
              full[11:20, c("year", "canonical_govid", "spend_subtype", "category")],
              ignore_attr = TRUE)
})

test_that("walking every page reconstructs the unpaginated result exactly", {
  skip_if_no_corpus()
  full <- cog_spending("121011212191", years = 2019:2020, category = NULL)
  n <- nrow(full)
  limit <- 7L
  pages <- list()
  offset <- 0L
  repeat {
    p <- cog_spending("121011212191", years = 2019:2020, category = NULL,
                      limit = limit, offset = offset)
    if (nrow(p) == 0L) break
    pages[[length(pages) + 1L]] <- p
    offset <- offset + limit
    if (offset > n + limit) stop("test runaway: paging did not terminate")
  }
  walked <- dplyr::bind_rows(pages)
  expect_equal(nrow(walked), n)
  key_cols <- c("year", "canonical_govid", "spend_subtype", "category", "amt_nominal")
  expect_equal(walked[key_cols], full[key_cols], ignore_attr = TRUE)
})

test_that("total_rows attribute reports the full unpaginated count", {
  skip_if_no_corpus()
  full <- cog_spending("121011212191", years = 2019:2020, category = NULL)
  page <- cog_spending("121011212191", years = 2019:2020, category = NULL,
                       limit = 5L, offset = 0L)
  expect_equal(attr(page, "total_rows"), nrow(full))
})

test_that("offset past the end returns zero rows, not an error", {
  skip_if_no_corpus()
  full <- cog_spending("121011212191", years = 2019:2020, category = NULL)
  page <- cog_spending("121011212191", years = 2019:2020, category = NULL,
                       limit = 10L, offset = nrow(full) + 100L)
  expect_equal(nrow(page), 0L)
  expect_equal(attr(page, "total_rows"), nrow(full))
})

test_that("limit is unset by default -- unpaginated calls are unaffected", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections")
  expect_null(attr(r, "total_rows"))
})

test_that("per_capita and adjust_to_year still apply correctly within a page", {
  skip_if_no_corpus()
  full <- cog_spending("121011212191", years = 2020L, category = NULL,
                       per_capita = TRUE, adjust_to_year = 2022L)
  page <- cog_spending("121011212191", years = 2020L, category = NULL,
                       per_capita = TRUE, adjust_to_year = 2022L,
                       limit = 3L, offset = 2L)
  expect_equal(page[c("amt_nominal", "amt_real", "amt_per_capita_nominal",
                      "amt_per_capita_real")],
              full[3:5, c("amt_nominal", "amt_real", "amt_per_capita_nominal",
                          "amt_per_capita_real")],
              ignore_attr = TRUE)
})

test_that("complete = TRUE with limit aborts -- pagination over a partial grid is undefined", {
  skip_if_no_corpus()
  expect_error(
    cog_spending("121011212191", 2020L, "Corrections", complete = TRUE, limit = 5L),
    class = "uscogdata_complete_pagination_conflict"
  )
})
