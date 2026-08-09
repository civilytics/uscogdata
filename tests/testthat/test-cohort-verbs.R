# The money verbs accepting a cohort by predicate (uscogdata#58).
#
# The load-bearing property is EQUIVALENCE: naming the same set of governments
# by id and by state/type must return the same rows. Everything else here is
# about the ways that equivalence could silently break -- the postal/FIPS
# translation, the intersection rule, and provenance no longer having an id
# list to describe.
#
# Fixture cohorts used: RI (fips 44) cities = 8 governments, DE (fips 10)
# counties = 3. Small on purpose; the size of the win is measured against the
# production corpus, not here.

# --- equivalence -----------------------------------------------------------

test_that("a predicate cohort returns exactly what the same ids return", {
  skip_if_no_corpus()
  with_fixture_corpus({
    ids <- cog_gov_search(NULL, state = "RI", type = "city")$canonical_govid
    expect_gt(length(ids), 1L)

    by_id   <- cog_spending(govid = ids, years = 2019)
    by_pred <- cog_spending(years = 2019, state = "RI", type = "city")

    # Compare the data itself, ignoring the provenance attribute -- which is
    # SUPPOSED to differ (see the scope tests below).
    expect_equal(
      as.data.frame(by_id[order(by_id$canonical_govid, by_id$category), ]),
      as.data.frame(by_pred[order(by_pred$canonical_govid, by_pred$category), ]),
      ignore_attr = TRUE
    )
    expect_gt(nrow(by_pred), 0L)
  })
})

test_that("equivalence holds for cog_revenue()", {
  skip_if_no_corpus()
  with_fixture_corpus({
    ids <- cog_gov_search(NULL, state = "DE", type = "county")$canonical_govid
    by_id   <- cog_revenue(govid = ids, years = 2019)
    by_pred <- cog_revenue(years = 2019, state = "DE", type = "county")
    expect_equal(nrow(by_id), nrow(by_pred))
    expect_equal(sum(by_id$amt_nominal), sum(by_pred$amt_nominal))
  })
})

test_that("equivalence holds for cog_balances()", {
  skip_if_no_corpus()
  with_fixture_corpus({
    ids <- cog_gov_search(NULL, state = "DE", type = "county")$canonical_govid
    by_id   <- cog_balances(govid = ids, years = 2019)
    by_pred <- cog_balances(years = 2019, state = "DE", type = "county")
    expect_equal(nrow(by_id), nrow(by_pred))
    expect_equal(sum(by_id$amt_nominal), sum(by_pred$amt_nominal))
  })
})

test_that("equivalence survives per_capita, adjust_to_year and pagination", {
  skip_if_no_corpus()
  with_fixture_corpus({
    ids <- cog_gov_search(NULL, state = "RI", type = "city")$canonical_govid

    # per_capita now keys its population lookup on the rows in the result
    # rather than on the requested cohort; these must stay identical.
    by_id   <- cog_spending(govid = ids, years = 2019, per_capita = TRUE,
                            adjust_to_year = 2020)
    by_pred <- cog_spending(years = 2019, state = "RI", type = "city",
                            per_capita = TRUE, adjust_to_year = 2020)
    expect_equal(by_id$amt_per_capita_nominal, by_pred$amt_per_capita_nominal)
    expect_equal(by_id$amt_per_capita_real, by_pred$amt_per_capita_real)
    expect_equal(by_id$pop_source, by_pred$pop_source)

    paged_id   <- cog_spending(govid = ids, years = 2019, limit = 5, offset = 5)
    paged_pred <- cog_spending(years = 2019, state = "RI", type = "city",
                               limit = 5, offset = 5)
    expect_equal(as.data.frame(paged_id), as.data.frame(paged_pred),
                 ignore_attr = TRUE)
    expect_identical(attr(paged_id, "total_rows"), attr(paged_pred, "total_rows"))
  })
})

test_that("a state-only predicate spans every type in that state", {
  skip_if_no_corpus()
  with_fixture_corpus({
    ids <- cog_gov_search(NULL, state = "DE", type = NULL)$canonical_govid
    by_id   <- cog_spending(govid = ids, years = 2019)
    by_pred <- cog_spending(years = 2019, state = "DE")
    expect_equal(nrow(by_id), nrow(by_pred))
  })
})

# --- the postal/FIPS trap --------------------------------------------------

test_that("a postal abbreviation resolves to rows, not to silence", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # canonical_fips_xwalk.fips_state holds "44", not "RI". A predicate built
    # from the raw parameter matches nothing and returns an empty result that
    # reads as "these governments reported nothing" -- the exact trap cog-api
    # hit. A zero-row result here is the regression.
    r <- cog_spending(years = 2019, state = "RI", type = "city")
    expect_gt(nrow(r), 0L)

    # And the FIPS form is accepted as the same cohort.
    expect_equal(nrow(cog_spending(years = 2019, state = "44", type = "city")),
                 nrow(r))
  })
})

test_that("an unknown state abbreviation aborts with a message that names the problem", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # Regression: `.state_abbrev_to_fips` is a named character vector, so `[[`
    # on an absent name threw base R's "subscript out of bounds" and the
    # curated message was unreachable.
    expect_error(cog_spending(years = 2019, state = "ZZ"),
                 class = "uscogdata_unknown_state")
    expect_error(cog_spending(years = 2019, state = "ZZ"),
                 "Unknown state abbreviation")
  })
})

# --- naming the cohort -----------------------------------------------------

test_that("naming no cohort at all is refused", {
  skip_if_no_corpus()
  with_fixture_corpus({
    expect_error(cog_spending(years = 2019), class = "uscogdata_no_cohort")
    expect_error(cog_revenue(years = 2019), class = "uscogdata_no_cohort")
    expect_error(cog_balances(years = 2019), class = "uscogdata_no_cohort")
  })
})

test_that("an empty govid vector still fails as it always did", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # Supplied-but-empty is a caller error, not "cohort named some other way".
    expect_error(cog_spending(character(0), 2019),
                 "must be a non-empty character vector")
  })
})

test_that("govid and state/type together intersect", {
  skip_if_no_corpus()
  with_fixture_corpus({
    cities   <- cog_gov_search(NULL, state = "RI", type = "city")$canonical_govid
    counties <- cog_gov_search(NULL, state = "DE", type = "county")$canonical_govid

    # The documented rule: the governments in `govid` that ALSO match the
    # predicate -- never one silently taking precedence over the other.
    both <- cog_spending(govid = c(cities, counties), years = 2019,
                         state = "RI", type = "city")
    only <- cog_spending(govid = cities, years = 2019)
    expect_equal(as.data.frame(both), as.data.frame(only), ignore_attr = TRUE)

    # A disjoint intersection is empty, not "whichever one won".
    none <- cog_spending(govid = counties, years = 2019,
                         state = "RI", type = "city")
    expect_equal(nrow(none), 0L)
  })
})

# --- provenance ------------------------------------------------------------

test_that("a govid cohort's provenance scope is untouched", {
  skip_if_no_corpus()
  with_fixture_corpus({
    ids <- cog_gov_search(NULL, state = "DE", type = "county")$canonical_govid
    prov <- attr(cog_spending(govid = ids, years = 2019), "provenance")
    expect_setequal(prov$scope$govids_found, ids)
    expect_length(prov$scope$govids_missing, 0L)
    # No cohort block: govids_found already describes this cohort exactly.
    expect_null(prov$scope$cohort)
  })
})

test_that("a predicate cohort describes itself instead of listing ids", {
  skip_if_no_corpus()
  with_fixture_corpus({
    prov <- attr(cog_spending(years = 2019, state = "DE", type = "county"),
                 "provenance")
    # Deliberately NOT the resolved id list: a fleet-scale cohort would put
    # 20,000 govids into every response body.
    expect_length(prov$scope$govids_found, 0L)
    expect_length(prov$scope$govids_missing, 0L)
    expect_identical(prov$scope$cohort$state, "DE")
    expect_identical(prov$scope$cohort$type, "county")
    expect_identical(prov$scope$cohort$n_governments, 3L)
  })
})

test_that("the cohort block counts the intersection, not the predicate alone", {
  skip_if_no_corpus()
  with_fixture_corpus({
    counties <- cog_gov_search(NULL, state = "DE", type = "county")$canonical_govid
    prov <- attr(
      cog_spending(govid = counties[1], years = 2019, state = "DE", type = "county"),
      "provenance"
    )
    expect_identical(prov$scope$cohort$n_governments, 1L)
  })
})

# --- the SQL actually changed ----------------------------------------------

test_that("a predicate cohort never renders the ids into the query", {
  skip_if_no_corpus()
  with_fixture_corpus({
    ids <- cog_gov_search(NULL, state = "RI", type = "city")$canonical_govid
    prov <- attr(cog_spending(years = 2019, state = "RI", type = "city"),
                 "provenance")
    sql <- prov$sql_query %||% prov$sql
    skip_if(is.null(sql), "provenance carries no SQL for this verb")
    # The whole point: cohort size does not enter the SQL string.
    for (id in ids) expect_false(grepl(id, sql, fixed = TRUE))
    expect_match(sql, "SELECT canonical_govid FROM canonical_fips_xwalk",
                 fixed = TRUE)
  })
})
