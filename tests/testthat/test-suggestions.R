# tests/testthat/test-suggestions.R
#
# cog_suggestions() (uscogdata#75): the exported form of .build_suggestions().
# Each equivalence test runs a verb with a category named, takes the years its
# rows cover, and checks that cog_suggestions() returns exactly the list the
# verb attached as provenance$suggestions.

verb_suggestions <- function(r) attr(r, "provenance")$suggestions

suggestion_ids <- function(sugg) {
  vapply(sugg, function(s) s$recipe_id, character(1))
}

test_that("cog_suggestions() matches cog_spending() on an empty_year fire", {
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("061037123085", years = 2011L, category = "Corrections"))
  expect_length(verb_suggestions(r), 3L)

  s <- cog_suggestions("061037123085", years = 2011L, category = "Corrections",
                       flow = "spending", years_present = unique(r$year))
  expect_identical(s, verb_suggestions(r))
  expect_identical(
    suggestion_ids(s),
    c("corrections_capital_combined", "corrections_combined",
      "corrections_other_capital_combined"))
})

test_that("cog_suggestions() matches cog_spending() on a suppressed_component fire", {
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("061037123085", years = 2011L, category = "Public Welfare"))
  expect_gt(nrow(r), 0L)
  expect_length(verb_suggestions(r), 2L)

  s <- cog_suggestions("061037123085", years = 2011L,
                       category = "Public Welfare", flow = "spending",
                       years_present = unique(r$year))
  expect_identical(s, verb_suggestions(r))
})

test_that("cog_suggestions() matches cog_spending() for a multi-government cohort", {
  skip_if_no_corpus()
  govids <- c("061037123085", "121011212191", "010000226085")
  r <- suppressMessages(
    cog_spending(govids, years = c(2011L, 2012L), category = "Corrections"))
  expect_gt(length(verb_suggestions(r)), 0L)

  s <- cog_suggestions(govids, years = c(2011L, 2012L),
                       category = "Corrections", flow = "spending",
                       years_present = unique(r$year))
  expect_identical(s, verb_suggestions(r))
})

test_that("cog_suggestions() accepts a data frame of governments", {
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("061037123085", years = 2011L, category = "Corrections"))
  s <- cog_suggestions(data.frame(canonical_govid = "061037123085"),
                       years = 2011L, category = "Corrections",
                       years_present = unique(r$year))
  expect_identical(s, verb_suggestions(r))
})

test_that("cog_suggestions() matches cog_revenue()", {
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_revenue("020000227749", years = 2011L,
                category = "Miscellaneous Revenue"))
  expect_length(verb_suggestions(r), 1L)

  s <- cog_suggestions("020000227749", years = 2011L,
                       category = "Miscellaneous Revenue", flow = "revenue",
                       years_present = unique(r$year))
  expect_identical(s, verb_suggestions(r))
})

test_that("cog_suggestions() matches cog_revenue() under revenue_concept = 'total'", {
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_revenue("020000227749", years = 2011L,
                category = "Miscellaneous Revenue", revenue_concept = "total"))
  s <- cog_suggestions("020000227749", years = 2011L,
                       category = "Miscellaneous Revenue", flow = "revenue",
                       concept = "total", years_present = unique(r$year))
  expect_identical(s, verb_suggestions(r))
})

test_that("cog_suggestions() matches the verbs for 'All Categories' under each concept", {
  skip_if_no_corpus()
  gov <- "010000226085"
  for (concept in c("primary", "direct")) {
    r <- suppressMessages(
      cog_spending(gov, 2011L, category = "All Categories",
                   expenditure_concept = concept))
    expect_gt(length(verb_suggestions(r)), 0L)
    s <- cog_suggestions(gov, 2011L, category = "All Categories",
                         concept = concept, years_present = unique(r$year))
    expect_identical(s, verb_suggestions(r), info = concept)
  }

  r <- suppressMessages(
    cog_revenue(gov, 2011L, category = "All Categories",
                revenue_concept = "total"))
  s <- cog_suggestions(gov, 2011L, category = "All Categories",
                       flow = "revenue", concept = "total",
                       years_present = unique(r$year))
  expect_identical(s, verb_suggestions(r))
})

test_that("cog_suggestions() matches expenditure_concept = 'total' given Direct-leg years", {
  # cog_spending() measures gaps on the Direct leg only (C1(a) in
  # R/suggestions.R), so the caller passes the years with a
  # non-intergovernmental row, as the years_present documentation says.
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("061037123085", years = 2011L, category = "Corrections",
                 expenditure_concept = "total"))
  expect_gt(length(verb_suggestions(r)), 0L)

  direct <- r[r$spend_subtype != "intergovernmental", ]
  s <- cog_suggestions("061037123085", years = 2011L,
                       category = "Corrections", concept = "total",
                       years_present = unique(direct$year))
  expect_identical(s, verb_suggestions(r))
})

test_that("cog_suggestions() returns an empty list when nothing qualifies", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", years = 2019:2020, category = "Corrections")
  expect_length(verb_suggestions(r), 0L)
  s <- cog_suggestions("121011212191", years = 2019:2020,
                       category = "Corrections",
                       years_present = unique(r$year))
  expect_identical(s, list())
})

test_that("cog_suggestions() follows the verbs to basis = 'raw' on a schema_version 4 corpus", {
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    expect_identical(
      cog_suggestions("061037123085", years = 2011L,
                      category = "Corrections", years_present = integer(0)),
      list())
  })
})

test_that("cog_suggestions() prints nothing", {
  skip_if_no_corpus()
  uscogdata:::.ensure_session()
  expect_silent(
    cog_suggestions("061037123085", years = 2011L, category = "Corrections",
                    years_present = integer(0)))
})

# --- stable order ------------------------------------------------------------

test_that("suggestions come back ordered by recipe_id, in the verbs and here", {
  # On the fixture, the unsorted candidate query lists
  # corrections_other_capital_combined before corrections_combined, so this
  # fails without the ORDER BY in .query_candidate_recipes().
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("010000226085", 2011L, category = "All Categories"))
  ids <- suggestion_ids(verb_suggestions(r))
  expect_gt(length(ids), 1L)
  expect_identical(ids, sort(ids, method = "radix"))

  s <- cog_suggestions("010000226085", 2011L, category = "All Categories",
                       years_present = unique(r$year))
  expect_identical(suggestion_ids(s), ids)
})

test_that("repeated cog_suggestions() calls return the same list in the same order", {
  skip_if_no_corpus()
  calls <- lapply(seq_len(10L), function(i) {
    cog_suggestions("010000226085", 2011L, category = "All Categories",
                    years_present = 2011L)
  })
  expect_gt(length(calls[[1]]), 1L)
  for (i in seq_along(calls)[-1L]) {
    expect_identical(calls[[i]], calls[[1]], info = paste("call", i))
  }
})

test_that(".query_candidate_recipes() returns recipe ids in sorted order", {
  con <- uscogdata:::.ensure_session()
  ids <- uscogdata:::.query_candidate_recipes(
    con, category = NULL, flow_prefixes = c("E", "F", "G"),
    all_categories = TRUE, subtype_col = "spend_subtype",
    subtype_scope = c("operations", "capital", "assistance"))
  expect_gt(length(ids), 1L)
  expect_identical(ids, sort(ids, method = "radix"))
})

# --- input validation --------------------------------------------------------

test_that("cog_suggestions() requires every argument without a default", {
  expect_error(
    cog_suggestions(years = 2011L, category = "Police", years_present = 2011L),
    "govid")
  expect_error(
    cog_suggestions("061037123085", category = "Police", years_present = 2011L),
    "years")
  expect_error(
    cog_suggestions("061037123085", years = 2011L, years_present = 2011L),
    "category")
  expect_error(
    cog_suggestions("061037123085", years = 2011L, category = "Police"),
    "years_present")
})

test_that("cog_suggestions() validates govid, years and category", {
  expect_error(
    cog_suggestions(character(0), 2011L, "Police", years_present = 2011L),
    "govid")
  expect_error(
    cog_suggestions(NA_character_, 2011L, "Police", years_present = 2011L),
    "govid")
  expect_error(
    cog_suggestions(list("061037123085"), 2011L, "Police",
                    years_present = 2011L),
    "govid")
  expect_error(
    cog_suggestions("061037123085", integer(0), "Police",
                    years_present = 2011L),
    "years")
  expect_error(
    cog_suggestions("061037123085", "2011", "Police", years_present = 2011L),
    "years")
  expect_error(
    cog_suggestions("061037123085", 2011L, NULL, years_present = 2011L),
    "category")
  expect_error(
    cog_suggestions("061037123085", 2011L, 1L, years_present = 2011L),
    "category")
  expect_error(
    cog_suggestions("061037123085", 2011L, c("Police", NA),
                    years_present = 2011L),
    "category")
  expect_error(
    cog_suggestions("061037123085", 2011L, c("All Categories", "Police"),
                    years_present = 2011L),
    class = "uscogdata_all_categories_not_combinable")
})

test_that("cog_suggestions() validates flow and concept against each other", {
  expect_error(
    cog_suggestions("061037123085", 2011L, "Police", flow = "balances",
                    years_present = 2011L),
    class = "uscogdata_invalid_flow")
  expect_error(
    cog_suggestions("061037123085", 2011L, "Police", flow = "spending",
                    concept = "general", years_present = 2011L),
    class = "uscogdata_invalid_expenditure_concept")
  expect_error(
    cog_suggestions("061037123085", 2011L, "Taxes", flow = "revenue",
                    concept = "primary", years_present = 2011L),
    class = "uscogdata_invalid_revenue_concept")
  expect_error(
    cog_suggestions("061037123085", 2011L, "Police",
                    concept = c("primary", "direct"), years_present = 2011L),
    class = "uscogdata_invalid_expenditure_concept")
})

test_that("cog_suggestions() validates years_present", {
  expect_error(
    cog_suggestions("061037123085", 2011L, "Police", years_present = NULL),
    "integer\\(0\\)")
  expect_error(
    cog_suggestions("061037123085", 2011L, "Police", years_present = "2011"),
    "years_present")
  expect_error(
    cog_suggestions("061037123085", 2011L, "Police",
                    years_present = NA_integer_),
    "years_present")
})

test_that("cog_suggestions() is exported", {
  expect_true("cog_suggestions" %in% getNamespaceExports("uscogdata"))
})
