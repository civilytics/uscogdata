# tests/testthat/test-recipes.R
#
# cog_recipes(), recipe = in cog_spending()/cog_revenue(), and the
# recipe-component-driven signposting in prov$suggestions (Phase R2 /
# Task 11, schema_version 5).

test_that("cog_recipes lists the curated catalog including corrections_combined", {
  skip_if_no_corpus()
  r <- cog_recipes()
  expect_s3_class(r, "tbl_df")
  expect_equal(names(r), c("recipe_id", "label", "n_components", "year_min", "year_max"))
  expect_equal(nrow(r), 24L)
  expect_true("corrections_combined" %in% r$recipe_id)
  expect_true("t19_selective_sales_wide" %in% r$recipe_id)
  expect_true("ig_federal_b89_wide" %in% r$recipe_id)
  expect_true("rents_royalties_u4_wide" %in% r$recipe_id)
  expect_true("higher_ed_e18_wide" %in% r$recipe_id)
  expect_true("cash_securities_z77_wide" %in% r$recipe_id)
  # Superseded id from the pre-curation brief text must NOT be present.
  expect_false("corrections_judicial_combined" %in% r$recipe_id)
})

test_that("cog_recipes(pattern=) filters by recipe_id or label", {
  skip_if_no_corpus()
  r <- cog_recipes("corrections")
  expect_true(nrow(r) >= 1L)
  expect_true(all(grepl("corrections", r$recipe_id, ignore.case = TRUE) |
                    grepl("corrections", r$label, ignore.case = TRUE)))
})

test_that("cog_recipes requires schema_version >= 5", {
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    expect_error(cog_recipes(), class = "uscogdata_schema_unsupported")
  })
})

# --- recipe = : generic join, no is_aggregate filter -----------------------

test_that("recipe = 'corrections_combined' is continuous across the 2011->2012 seam", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", years = c(2011L, 2012L),
                    recipe = "corrections_combined")
  expect_equal(nrow(r), 2L)
  expect_true(all(c("year", "canonical_govid", "gov_name", "spend_subtype",
                    "category", "amt_nominal", "codes_included",
                    "aggregate_fallback", "notes") %in% names(r)))
  expect_equal(unique(r$spend_subtype), "recipe")
  expect_equal(unique(r$category), "Corrections (functions 04+05 combined)")
  expect_false(any(r$aggregate_fallback))

  r2011 <- r$amt_nominal[r$year == 2011L]
  r2012 <- r$amt_nominal[r$year == 2012L]
  # 2011: E05 only exists as a wide-era AGGREGATE row (is_aggregate = TRUE)
  # for Broward -- data-verified $216,088,000. Since .run_recipe() does NOT
  # filter is_aggregate (amendment: the recipe join must not, because these
  # families exist ONLY as aggregate rows in the wide era), the recipe
  # correctly picks this up.
  expect_equal(r2011, 216088000)
  # 2012: modern E04 leaf ($213,056,000); Broward reports no E05 leaf that
  # year, so the recipe total equals E04 alone -- still continuous with the
  # 2011 aggregate, proving the wide-aggregate -> modern-leaf handoff.
  expect_equal(r2012, 213056000)
  expect_true(all(grepl("E04|E05", r$codes_included)))
})

test_that("recipe result carries a recipe provenance block with component rows", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", years = c(2011L, 2012L),
                    recipe = "corrections_combined")
  prov <- attr(r, "provenance")
  expect_equal(prov$basis, "recipe")
  expect_equal(prov$category, "Corrections (functions 04+05 combined)")
  expect_type(prov$recipe, "list")
  expect_equal(prov$recipe$recipe_id, "corrections_combined")
  expect_equal(prov$recipe$label, "Corrections (functions 04+05 combined)")
  expect_length(prov$recipe$components, 2L)
  comp_codes <- vapply(prov$recipe$components, function(x) x$component_code, character(1))
  expect_setequal(comp_codes, c("E04", "E05"))
  # A recipe query resolves its own coverage; it should never also carry
  # suggestions for itself.
  expect_length(prov$suggestions, 0L)
})

test_that("recipe results report an unambiguous basis/harmonization, ignoring basis=", {
  skip_if_no_corpus()
  # A recipe query bypasses spending_annotated(_harmonized) entirely --
  # .run_recipe() joins `long` directly -- so `basis` must never read
  # "harmonized"/"raw" (which would describe a code path this query never
  # took) regardless of what the caller passed for `basis`. Task 12
  # consumes provenance verbatim, so this needs to be unambiguous.
  r_default <- cog_spending("121011212191", years = c(2011L, 2012L),
                            recipe = "corrections_combined")
  r_raw <- cog_spending("121011212191", years = c(2011L, 2012L),
                        recipe = "corrections_combined", basis = "raw")
  r_harm <- cog_spending("121011212191", years = c(2011L, 2012L),
                         recipe = "corrections_combined", basis = "harmonized")

  for (r in list(r_default, r_raw, r_harm)) {
    prov <- attr(r, "provenance")
    expect_equal(prov$basis, "recipe")
    expect_true(is.na(prov$basis_note))
    expect_false(prov$harmonization$applied)
    expect_equal(prov$harmonization$na_rows_excluded, 0L)
    expect_match(prov$harmonization$note, "recipe", ignore.case = TRUE)
  }

  # basis= truly has zero effect on a recipe query's actual numbers.
  expect_equal(r_raw$amt_nominal, r_harm$amt_nominal)
  expect_equal(r_default$amt_nominal, r_raw$amt_nominal)
})

test_that("recipe = 't19_selective_sales_wide' sums the local T11/T14 legs when present", {
  skip_if_no_corpus()
  # Westminster City, CA (canonical_govid 082001211654): T11 = 0 in 2011,
  # T11 = 568 (T14 = 0/absent) in 2012 -- a real, data-verified equality/
  # inequality pair inside the amended fixture window (2011-2012), standing
  # in for the brief's original 2004/2005 example (out of scope per the
  # amended fixture years; the underlying local-tax-split boundary is
  # nationally FY2005, but this government's own T11 reporting activates
  # within our 2011-2012 window).
  r <- cog_revenue("082001211654", years = c(2011L, 2012L),
                   recipe = "t19_selective_sales_wide")

  # Raw, single-code T19 total (not the "Other Taxes" category total, which
  # would also sum in T11/T14/T21/T23/T27/T29/T53/T99 -- queried directly to
  # isolate exactly the code the brief's equality/inequality check is about).
  con <- uscogdata:::.ensure_session()
  raw_t19 <- DBI::dbGetQuery(con, "
    SELECT year, SUM(amt) * 1000.0 AS amt
    FROM revenue_long
    WHERE canonical_govid = '082001211654' AND item_code = 'T19'
      AND year IN (2011, 2012)
    GROUP BY year ORDER BY year
  ")
  raw_t19_2011 <- raw_t19$amt[raw_t19$year == 2011L]
  raw_t19_2012 <- raw_t19$amt[raw_t19$year == 2012L]
  expect_equal(raw_t19_2011, 2231000)
  expect_equal(raw_t19_2012, 2365000)

  recipe_2011 <- r$amt_nominal[r$year == 2011L]
  recipe_2012 <- r$amt_nominal[r$year == 2012L]

  expect_equal(recipe_2011, raw_t19_2011)       # equality: no local T11/T14 yet
  expect_gt(recipe_2012, raw_t19_2012)          # inequality: local T11 joins in
  expect_equal(recipe_2012, raw_t19_2012 + 568000)
})

test_that("recipe = and category = together aborts", {
  skip_if_no_corpus()
  expect_error(
    cog_spending("121011212191", 2020L, category = "Corrections",
                recipe = "corrections_combined"),
    class = "uscogdata_recipe_category_conflict"
  )
})

test_that("unknown recipe id aborts and lists valid ids", {
  skip_if_no_corpus()
  err <- tryCatch(
    cog_spending("121011212191", 2020L, recipe = "does_not_exist"),
    error = identity
  )
  expect_s3_class(err, "uscogdata_unknown_recipe")
  expect_match(conditionMessage(err), "corrections_combined")
})

test_that("recipe = requires schema_version >= 5", {
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    expect_error(
      cog_spending("121011212191", 2020L, recipe = "corrections_combined"),
      class = "uscogdata_schema_unsupported"
    )
  })
})

# --- signposting -------------------------------------------------------

test_that("signposting suggests corrections_combined across the 2011->2012 gap", {
  skip_if_no_corpus()
  expect_message(
    r <- cog_spending("121011212191", years = c(2011L, 2012L),
                      category = "Corrections"),
    "recipe"
  )
  prov <- attr(r, "provenance")
  expect_true(length(prov$suggestions) >= 1L)
  ids <- vapply(prov$suggestions, function(s) s$recipe_id, character(1))
  expect_true("corrections_combined" %in% ids)
  hit <- prov$suggestions[[which(ids == "corrections_combined")]]
  expect_equal(hit$hint, "re-run with recipe = 'corrections_combined'")
  expect_equal(hit$available_years, c(1967L, 2023L))
})

test_that("no signposting when the result already has full year coverage", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", years = 2019:2020, category = "Corrections")
  prov <- attr(r, "provenance")
  expect_length(prov$suggestions, 0L)
})

test_that("no signposting when category is NULL (unscoped query)", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", years = c(2011L, 2012L))
  prov <- attr(r, "provenance")
  expect_length(prov$suggestions, 0L)
})

test_that("no signposting under basis = 'raw'", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", years = c(2011L, 2012L),
                    category = "Corrections", basis = "raw")
  prov <- attr(r, "provenance")
  expect_length(prov$suggestions, 0L)
})

# --- uscogdata#9: partial-coverage signposting ------------------------------

test_that("no recipe component is ever renamed by harmonization", {
  # The suppression trigger anti-joins the verb's long view on item_code.
  # That is only sound because harmonization never rewrites a recipe
  # component's code -- every component whose harmonized_code differs has
  # harmonized_code IS NULL (and is aggregate-flagged). If this ever fails,
  # .suppressed_components() would report reachable dollars as suppressed.
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS renamed FROM long
     WHERE item_code IN (SELECT DISTINCT component_code FROM harmonization_recipes)
       AND harmonized_code IS NOT NULL
       AND harmonized_code <> item_code")$renamed
  expect_equal(as.integer(n), 0L)
})

test_that(".select_long_view maps annotated view bases to their long views", {
  expect_equal(
    uscogdata:::.select_long_view("spending_annotated", "harmonized"),
    "spending_long_harmonized")
  expect_equal(
    uscogdata:::.select_long_view("revenue_annotated", "harmonized"),
    "revenue_long_harmonized")
  expect_equal(
    uscogdata:::.select_long_view("spending_annotated", "raw"),
    "spending_long")
})

test_that(".suppressed_components measures the E67/E68 dollars Public Welfare drops", {
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  s <- uscogdata:::.suppressed_components(
    con,
    candidates = c("welfare_cash_e67_wide", "welfare_cash_e68_wide"),
    govid = "061037123085", years = 2011L,
    long_view = "spending_long_harmonized")

  expect_s3_class(s, "tbl_df")
  expect_equal(nrow(s), 2L)
  s <- s[order(s$recipe_id), ]
  expect_equal(s$recipe_id, c("welfare_cash_e67_wide", "welfare_cash_e68_wide"))
  expect_equal(s$suppressed_amount, c(1803872000, 271589000))
  expect_equal(s$suppressed_codes, c("E67", "E68"))
})

test_that(".suppressed_components finds nothing in a modern year", {
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  s <- uscogdata:::.suppressed_components(
    con,
    candidates = c("welfare_cash_e67_wide", "welfare_cash_e68_wide"),
    govid = "061037123085", years = 2019L,
    long_view = "spending_long_harmonized")
  expect_equal(nrow(s), 0L)
})

test_that(".suppressed_components rejects a long_view outside the allowlist", {
  skip_if_no_corpus()
  con <- uscogdata:::.ensure_session()
  expect_error(
    uscogdata:::.suppressed_components(
      con, candidates = "welfare_cash_e67_wide", govid = "061037123085",
      years = 2011L, long_view = "long; DROP TABLE x"),
    class = "uscogdata_internal_error")
})
