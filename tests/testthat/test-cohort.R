# A cohort is how every verb names the set of governments it queries. It can be
# named by explicit id, by a predicate over canonical_fips_xwalk, or by both
# (intersection). These tests cover the SQL construction itself -- pure string
# building, no corpus needed -- because that is where the postal/FIPS trap and
# the 40k-literal blowup both live.

test_that(".make_cohort() keeps an explicit id vector as ids", {
  ch <- .make_cohort(govid = c("550000227544", "060000000001"))
  expect_identical(ch$ids, c("550000227544", "060000000001"))
  expect_null(ch$state_fips)
  expect_null(ch$type_int)
  expect_false(.cohort_by_predicate(ch))
})

test_that(".make_cohort() translates a postal abbreviation to FIPS", {
  # The trap this whole issue exists to avoid: canonical_fips_xwalk.fips_state
  # holds "55", not "WI". A predicate written against the raw parameter matches
  # nothing and returns an empty result that reads as "reported nothing".
  ch <- .make_cohort(state = "WI")
  expect_identical(ch$state_fips, "55")
  expect_true(.cohort_by_predicate(ch))
})

test_that(".make_cohort() translates a type label to its integer code", {
  expect_identical(.make_cohort(type = "city")$type_int, 2L)
  expect_identical(.make_cohort(type = "state")$type_int, 0L)
  expect_identical(.make_cohort(type = 1)$type_int, 1L)
})

test_that(".make_cohort() reuses the search verb's coercers for invalid input", {
  expect_error(.make_cohort(state = "ZZ"), "Unknown state abbreviation")
  expect_error(.make_cohort(type = "special_district"), "Unknown type")
  # Out-of-scope types (4 = special district, 5 = school district) are refused
  # by the numeric branch, with the v0.1-scope message.
  expect_error(.make_cohort(type = 4), "type must be 0, 1, 2, or 3")
})

test_that(".make_cohort() rejects naming no cohort at all", {
  expect_error(.make_cohort(), class = "uscogdata_no_cohort")
})

test_that(".cohort_sql() renders an id cohort as a literal IN list", {
  sql <- .cohort_sql(.make_cohort(govid = c("a", "b")))
  expect_identical(sql, "canonical_govid IN ('a','b')")
})

test_that(".cohort_sql() renders a predicate cohort as an xwalk subquery", {
  # The point of the issue: the cohort never becomes a literal list, so its
  # size does not enter the SQL string at all.
  sql <- .cohort_sql(.make_cohort(state = "WI", type = "city"))
  expect_match(sql, "SELECT canonical_govid FROM canonical_fips_xwalk", fixed = TRUE)
  expect_match(sql, "fips_state = '55'", fixed = TRUE)
  expect_match(sql, "govs_type = 2", fixed = TRUE)
  expect_false(grepl("'WI'", sql, fixed = TRUE))
})

test_that(".cohort_sql() renders ids and a predicate as an intersection", {
  sql <- .cohort_sql(.make_cohort(govid = c("a", "b"), type = "city"))
  expect_match(sql, "canonical_govid IN ('a','b')", fixed = TRUE)
  expect_match(sql, "AND canonical_govid IN (SELECT", fixed = TRUE)
})

test_that(".cohort_sql() honours a column alias", {
  # Several call sites join the xwalk under an alias (`l.`, `x.`, `v.`), so the
  # predicate has to be able to name the qualified column.
  sql <- .cohort_sql(.make_cohort(state = "WI"), col = "l.canonical_govid")
  expect_match(sql, "l.canonical_govid IN (SELECT", fixed = TRUE)
  # The subquery's own column stays unqualified -- it selects from the xwalk,
  # not from the outer relation.
  expect_match(sql, "SELECT canonical_govid FROM", fixed = TRUE)
})

test_that(".cohort_sql() escapes quotes in ids", {
  sql <- .cohort_sql(.make_cohort(govid = "o'brien"))
  expect_match(sql, "'o''brien'", fixed = TRUE)
})

test_that("a predicate cohort's SQL does not grow with cohort size", {
  # The regression this guards: 20,106 ids rendered to a 301,591-character
  # IN list, embedded in 5-8 statements per call.
  wide <- .cohort_sql(.make_cohort(state = "CA", type = "city"))
  expect_lt(nchar(wide), 200L)
})
