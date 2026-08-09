# Baseline at branch point: 843 PASS / 0 FAIL / 0 SKIP / 0 WARN (2026-08-05, origin/main 2fc9e75)

test_that(".build_verb_sql emits a literal category and no category filter in all-categories mode", {
  sql <- uscogdata:::.build_verb_sql(
    view         = "spending_annotated",
    subtype_col  = "spend_subtype",
    cohort = uscogdata:::.make_cohort("552025209777"),
    years        = 2019L,
    category     = NULL,
    subtype_scope = c("operations", "capital"),
    all_categories = TRUE
  )

  expect_match(sql, "'All Categories' AS category", fixed = TRUE)
  # no category filter of any kind
  expect_false(grepl("AND category IN", sql, fixed = TRUE))
  # category is not a grouping key
  expect_false(grepl("GROUP BY year, canonical_govid, gov_name, xwalk_gov_name, spend_subtype, category",
                     sql, fixed = TRUE))
  # the subtype allowlist still applies -- this is what makes the sum a concept
  expect_match(sql, "AND spend_subtype IN ('operations','capital')", fixed = TRUE)
})

test_that(".build_verb_sql is unchanged when all_categories is FALSE", {
  args <- list(
    view = "spending_annotated", subtype_col = "spend_subtype",
    cohort = uscogdata:::.make_cohort("552025209777"), years = 2019L, category = NULL,
    subtype_scope = c("operations", "capital")
  )
  old <- do.call(uscogdata:::.build_verb_sql, args)
  new <- do.call(uscogdata:::.build_verb_sql, c(args, list(all_categories = FALSE)))
  expect_identical(old, new)
  expect_match(new, "GROUP BY year, canonical_govid, gov_name, xwalk_gov_name, spend_subtype, category",
               fixed = TRUE)
})

test_that(".ALL_CATEGORIES is the exact reserved string", {
  expect_identical(uscogdata:::.ALL_CATEGORIES, "All Categories")
})

test_that('cog_spending(category = "All Categories") sums to the per-category total', {
  gov <- "552025209777"
  by_cat <- cog_spending(gov, 2019L)
  total  <- cog_spending(gov, 2019L, category = "All Categories")

  expect_true(nrow(total) > 0L)
  expect_setequal(unique(total$category), "All Categories")
  # one row per subtype present in the by-category result
  expect_setequal(unique(total$spend_subtype), unique(by_cat$spend_subtype))
  expect_equal(nrow(total), length(unique(by_cat$spend_subtype)))

  # the dollars agree, per subtype
  lhs <- tapply(by_cat$amt_nominal, by_cat$spend_subtype, sum)
  rhs <- tapply(total$amt_nominal,  total$spend_subtype,  sum)
  expect_equal(as.numeric(rhs[names(lhs)]), as.numeric(lhs), tolerance = 1e-8)
})

test_that('"All Categories" respects expenditure_concept', {
  gov <- "552025209777"
  prim <- cog_spending(gov, 2019L, category = "All Categories",
                       expenditure_concept = "primary")
  dir  <- cog_spending(gov, 2019L, category = "All Categories",
                       expenditure_concept = "direct")
  # direct = primary plus interest and insurance benefits, so it is never smaller
  expect_gte(sum(dir$amt_nominal), sum(prim$amt_nominal))
})

test_that('"All Categories" works on revenue and respects revenue_concept', {
  gov <- "552025209777"
  gen <- cog_revenue(gov, 2019L, category = "All Categories",
                     revenue_concept = "general")
  tot <- cog_revenue(gov, 2019L, category = "All Categories",
                     revenue_concept = "total")
  expect_setequal(unique(gen$category), "All Categories")
  expect_gte(sum(tot$amt_nominal), sum(gen$amt_nominal))
})

test_that('"All Categories" cannot be combined with another category', {
  expect_error(
    cog_spending("552025209777", 2019L, category = c("All Categories", "Police")),
    class = "uscogdata_all_categories_not_combinable"
  )
})

test_that('"All Categories" is recorded in provenance', {
  r <- cog_spending("552025209777", 2019L, category = "All Categories")
  expect_identical(cog_explain(r, format = "list")$category, "All Categories")
})

test_that('"All Categories" combines with subtype to give operating totals', {
  gov <- "552025209777"
  ops_by_cat <- cog_spending(gov, 2019L)
  ops_by_cat <- ops_by_cat[ops_by_cat$spend_subtype == "operations", ]
  ops_total  <- cog_spending(gov, 2019L, category = "All Categories")
  ops_total  <- ops_total[ops_total$spend_subtype == "operations", ]
  expect_equal(sum(ops_total$amt_nominal), sum(ops_by_cat$amt_nominal),
               tolerance = 1e-8)
})

test_that('cog_categories() advertises "All Categories" for both flows', {
  all <- cog_categories()
  rows <- all[all$category == "All Categories", ]
  expect_setequal(rows$category_type, c("expenditure", "revenue"))
  expect_true(all(is.na(rows$subtype)))
  expect_true(all(is.na(rows$n_codes)))
})

test_that('cog_categories(type=) still scopes, including the pseudo-category', {
  sp <- cog_categories(type = "spending")
  expect_setequal(unique(sp$category_type), "expenditure")
  expect_true("All Categories" %in% sp$category)

  rev <- cog_categories(type = "revenue")
  expect_setequal(unique(rev$category_type), "revenue")
  expect_true("All Categories" %in% rev$category)

  # balances have no concept vocabulary, so no pseudo-category
  bal <- cog_categories(type = "balance")
  expect_false("All Categories" %in% bal$category)
})

test_that('cog_categories(pattern=) matches the pseudo-category', {
  hit <- cog_categories(pattern = "^All Categories$")
  expect_equal(nrow(hit), 2L)
})

# --- final whole-branch review fixes ---------------------------------------

test_that('complete = TRUE is refused when combined with "All Categories"', {
  # .completion_grid_sql() would emit `AND c.category IN ('All Categories')`,
  # match zero crosswalk rows, and the early return in .complete_result()
  # would stamp completion$applied = TRUE, rows_filled = 0 -- reading as "the
  # grid was checked and nothing was missing" when nothing was actually
  # checked. Filling a summed row has no defined semantics, so the verb must
  # refuse the combination outright (finding 2).
  expect_error(
    cog_spending("552025209777", 2019L, category = "All Categories",
                complete = TRUE),
    class = "uscogdata_complete_unsupported"
  )
  expect_error(
    cog_revenue("552025209777", 2019L, category = "All Categories",
               complete = TRUE),
    class = "uscogdata_complete_unsupported"
  )
})

test_that('cog_balances() rejects "All Categories" instead of silently returning zero rows', {
  # cog_balances() reuses .validate_verb_inputs() but did not pass
  # allow_all_categories = TRUE, so "All Categories" used to become
  # `AND category IN ('All Categories')` against balance_annotated -- 0
  # matching crosswalk rows, 0 rows back, no error (finding 3). Holdings are
  # a stock with no concept vocabulary to sum across, so the honest answer is
  # to refuse, the same way cog_spending()/cog_revenue() refuse other
  # nonsensical combinations.
  expect_error(
    cog_balances("552025209777", 2019L, category = "All Categories"),
    class = "uscogdata_all_categories_unsupported"
  )
  # An ordinary category still works -- this is not a blanket regression.
  r <- suppressMessages(
    cog_balances("552025209777", 2019L, category = "Fund Balances")
  )
  expect_gt(nrow(r), 0L)
})

test_that('expenditure_concept_direct_suppressed is NA, not FALSE, when categories are collapsed', {
  # .detect_direct_suppressed() keys on
  # paste(year, canonical_govid, category, sep = "\r"). In all-categories
  # mode every row carries the literal "All Categories" value, so an IG-only
  # row's key collides with any ordinary Direct row for the same
  # (year, govid) -- has_direct reads TRUE whenever the government has ANY
  # direct spending at all, candidate is always empty, and the detector can
  # never fire. Before the fix this silently reported FALSE, an affirmative
  # claim the code did not actually compute (finding 1). NA is the honest
  # answer: cog_explain(x, format = "list") is required here, since without
  # format = "list" it returns the result tibble, not the provenance list.
  gov <- "552025209777"
  t <- cog_spending(gov, 2019L, category = "All Categories",
                    expenditure_concept = "total")
  prov <- cog_explain(t, format = "list")
  expect_true(is.na(prov$expenditure_concept_direct_suppressed))
  expect_false(isTRUE(prov$expenditure_concept_direct_suppressed))
  expect_match(prov$expenditure_concept_note, "unavailable", fixed = TRUE)

  # A per-category "total" query on the same government/year is unaffected --
  # the detector can still key correctly and reports a strict logical.
  t_by_cat <- cog_spending(gov, 2019L, expenditure_concept = "total")
  prov_by_cat <- cog_explain(t_by_cat, format = "list")
  expect_false(is.na(prov_by_cat$expenditure_concept_direct_suppressed))
})

test_that('"All Categories" still signposts coverage gaps (finding 6, final whole-branch review)', {
  # .build_suggestions()'s candidate sub-select used to be keyed on
  # `category`, e.g. `WHERE category IN ('All Categories')`. Since
  # .ALL_CATEGORIES is never itself a row in summary_categories.category,
  # that sub-select always came back empty in all-categories mode, so
  # `candidates` was empty and .build_suggestions() short-circuited to
  # list() -- coverage signposting was structurally impossible for the one
  # mode whose whole selling point is "you cannot sum the wrong scope"
  # (uscogdata#9's entire point, silently defeated).
  #
  # AL state government, FY2011, category = "Corrections": this category has
  # no legacy leaf rows in FY2011 (aggregate-flagged E04/E05 family), so the
  # per-category query returns 0 rows and 3 recipe-hint suggestions fire
  # (empty_year path). All-categories mode does not have an empty year --
  # the government has other primary spending in FY2011 -- but the same
  # suppressed Corrections dollars are still excluded from the summed total,
  # so the fix (scoping the candidate sub-select by subtype_col/subtype_scope
  # instead of by category, symmetric with .build_verb_sql()) must still
  # surface them via the suppressed_component path.
  gov <- "010000226085"

  by_cat <- suppressMessages(cog_spending(gov, 2011L, category = "Corrections"))
  sugg_by_cat <- cog_explain(by_cat, format = "list")$suggestions
  expect_gt(length(sugg_by_cat), 0L)

  all_cat <- suppressMessages(cog_spending(gov, 2011L, category = "All Categories"))
  sugg_all_cat <- cog_explain(all_cat, format = "list")$suggestions
  expect_gt(length(sugg_all_cat), 0L)

  # The same Corrections recipe that fired per-category must also fire in
  # all-categories mode -- not just some unrelated recipe.
  ids_by_cat <- vapply(sugg_by_cat, function(s) s$recipe_id %||% "", character(1))
  ids_all_cat <- vapply(sugg_all_cat, function(s) s$recipe_id %||% "", character(1))
  expect_true("corrections_combined" %in% ids_by_cat)
  expect_true("corrections_combined" %in% ids_all_cat)

  # In all-categories mode the government DOES have other primary spending
  # in FY2011 (the year itself is not a gap), so the suggestion can only have
  # fired via the suppressed_component path, not empty_year.
  corr_all <- sugg_all_cat[[which(ids_all_cat == "corrections_combined")]]
  expect_identical(corr_all$trigger, "suppressed_component")
  expect_gt(corr_all$suppressed_amount, 0)
})

test_that('"All Categories" candidate scoping is symmetric with .build_verb_sql() -- subtype, not category', {
  # Direct assertion on the mechanism itself (finding 6): in all-categories
  # mode .build_suggestions() must scope its candidate recipe sub-select by
  # subtype_col/subtype_scope, not by the literal "All Categories" value.
  # Passing all_categories = FALSE with the identical category value proves
  # the branch -- not merely the subtype_col/subtype_scope arguments' mere
  # presence -- is what changes the query.
  con <- uscogdata:::.ensure_session()

  none <- uscogdata:::.build_suggestions(
    con, cohort = uscogdata:::.make_cohort("010000226085"), years = 2011L,
    category = "All Categories", result = NULL, basis = "harmonized",
    flow_prefixes = c("E", "F", "G"),
    long_view = "spending_long_harmonized",
    all_categories = FALSE,
    subtype_col = "spend_subtype",
    subtype_scope = c("operations", "capital", "assistance")
  )
  expect_length(none, 0L)

  scoped <- uscogdata:::.build_suggestions(
    con, cohort = uscogdata:::.make_cohort("010000226085"), years = 2011L,
    category = "All Categories", result = NULL, basis = "harmonized",
    flow_prefixes = c("E", "F", "G"),
    long_view = "spending_long_harmonized",
    all_categories = TRUE,
    subtype_col = "spend_subtype",
    subtype_scope = c("operations", "capital", "assistance")
  )
  expect_gt(length(scoped), 0L)
})
