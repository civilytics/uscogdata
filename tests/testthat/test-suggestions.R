# tests/testthat/test-suggestions.R

verb_suggestions <- function(r) attr(r, "provenance")$suggestions

suggestion_ids <- function(sugg) {
  vapply(sugg, function(s) s$recipe_id, character(1))
}

# --- stable order ------------------------------------------------------------

test_that("cog_spending() returns suggestions ordered by recipe_id", {
  # On the fixture, the unsorted candidate query lists
  # corrections_other_capital_combined before corrections_combined, so this
  # fails without the ORDER BY in .query_candidate_recipes().
  skip_if_no_corpus()
  r <- suppressMessages(
    cog_spending("010000226085", 2011L, category = "All Categories"))
  ids <- suggestion_ids(verb_suggestions(r))
  expect_gt(length(ids), 1L)
  expect_identical(ids, sort(ids, method = "radix"))
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
