# tests/testthat/test-complete.R
#
# uscogdata#18. The published corpus no longer stores the wide era's explicit
# zeros (cog_pipeline#64, series break SB194), so absence means two different
# things:
#
#   <= FY2011 (dense_source) : cell absent => Census published $0
#   >= FY2012 (sparse_source): cell absent => not reported, unknown
#
# `complete = TRUE` fills the requested grid from `code_set` and stamps every
# row's `value_source` so the two are distinguishable. Expected row sets here
# are built from the corpus parquet directly, never from the verb under test --
# verifying what a filter does through that same filter proves nothing.

# The (subtype, category) cells that SHOULD exist for one government-year:
# every code in force for that government's type, mapped through
# summary_categories, matching the verb's crosswalk subtype scope (the
# default concept, `primary`, is operations/capital/assistance -- see
# uscogdata#11) and excluding aggregate-flagged codes (which
# spending_long/revenue_long drop).
raw_expected_cells <- function(govid, year, subtypes, subtype_col) {
  fx <- sub("/$", "", Sys.getenv("USCOGDATA_URL"))
  q <- function(f) sprintf("read_parquet('%s/data/%s')", fx, f)
  wt_raw_query(sprintf(
    "SELECT DISTINCT c.%s AS subtype, c.category
     FROM %s cs
     JOIN %s x ON x.govs_type = cs.type
     JOIN %s c ON c.item_code = cs.item_code
     WHERE x.canonical_govid = '%s'
       AND cs.year = %d
       AND NOT cs.is_aggregate
       AND c.category IS NOT NULL
       AND c.%s IN (%s)",
    subtype_col, q("code_set.parquet"), q("canonical_fips_xwalk.parquet"),
    q("summary_categories.parquet"), govid, year,
    subtype_col, paste0("'", subtypes, "'", collapse = ",")
  ))
}

# The default expenditure concept's subtype scope, mirrored from
# R/spending.R's .spend_subtypes_primary.
primary_subtypes <- c("operations", "capital", "assistance")

test_that("complete = FALSE is the default and changes nothing", {
  skip_if_no_corpus()
  with_fixture_corpus({
    plain <- cog_spending("121011212191", 2011L)
    explicit <- cog_spending("121011212191", 2011L, complete = FALSE)
    expect_equal(nrow(plain), nrow(explicit))
    expect_false("value_source" %in% names(plain))
  })
})

test_that("complete = TRUE round-trips a dense-source year to the pre-sparsification cells", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # FY2011 is dense_source: before sparsification this government carried a
    # row for every code in force, most of them $0. complete = TRUE must
    # reproduce that cell set exactly.
    r <- cog_spending("121011212191", 2011L, complete = TRUE)
    expected <- raw_expected_cells("121011212191", 2011L,
                                   primary_subtypes, "spend_subtype")

    key <- function(sub, cat) paste(sub, cat, sep = "|")
    expect_setequal(key(r$spend_subtype, r$category),
                    key(expected$subtype, expected$category))
    expect_gt(nrow(expected), 0L)

    # Every filled cell in a dense-source year is a Census-published $0 --
    # never "unknown", which is what the modern era's absences mean.
    expect_setequal(unique(r$value_source), c("reported", "census_zero"))
    expect_true(all(r$amt_nominal[r$value_source == "census_zero"] == 0))
    expect_true(all(r$amt_nominal[r$value_source == "reported"] != 0))
  })
})

test_that("complete = TRUE preserves the reported rows and their amounts exactly", {
  skip_if_no_corpus()
  with_fixture_corpus({
    plain <- cog_spending("121011212191", 2011L)
    full  <- cog_spending("121011212191", 2011L, complete = TRUE)

    # Filling adds rows; it must never alter or drop one.
    expect_gt(nrow(full), nrow(plain))
    reported <- full[full$value_source == "reported", ]
    expect_equal(nrow(reported), nrow(plain))
    expect_equal(sum(reported$amt_nominal), sum(plain$amt_nominal))
    # ... and the total is unchanged, because every added cell is $0.
    expect_equal(sum(full$amt_nominal, na.rm = TRUE), sum(plain$amt_nominal))
  })
})

test_that("a sparse-source year's absences are unknown, not zero", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # FY2019 is sparse_source: an absent cell means the government did not
    # report, which is NOT a zero. Filling those with 0 would invent data --
    # the exact error the representation contract exists to prevent.
    r <- cog_spending("121011212191", 2019L, complete = TRUE)
    filled <- r[r$value_source != "reported", ]
    expect_gt(nrow(filled), 0L)
    expect_true(all(filled$value_source == "not_reported"))
    expect_true(all(is.na(filled$amt_nominal)))
    expect_false(any(r$value_source == "census_zero"))
  })
})

test_that("the fill is scoped to each government's own type", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # Filling against the union of all types would invent cells for codes a
    # county can never report. Every filled category must be one that
    # code_set puts in force for type 1 (county) specifically.
    r <- cog_spending("121011212191", 2011L, complete = TRUE)
    county_cells <- raw_expected_cells("121011212191", 2011L,
                                       primary_subtypes, "spend_subtype")
    expect_true(all(r$category %in% county_cells$category))
  })
})

test_that("complete = TRUE respects the category filter", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", 2011L, category = "Police",
                      complete = TRUE)
    expect_true(all(r$category == "Police"))
    expect_true("value_source" %in% names(r))
  })
})

test_that("cog_revenue() completes on its own flow", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_revenue("121011212191", 2011L, complete = TRUE)
    expected <- raw_expected_cells("121011212191", 2011L,
                                   c("own_source", "federal", "state", "local_aid"),
                                   "revenue_subtype")
    key <- function(sub, cat) paste(sub, cat, sep = "|")
    expect_setequal(key(r$revenue_subtype, r$category),
                    key(expected$subtype, expected$category))
    expect_setequal(unique(r$value_source), c("reported", "census_zero"))
  })
})

test_that("provenance records the completion and its absence rule", {
  skip_if_no_corpus()
  with_fixture_corpus({
    prov <- attr(cog_spending("121011212191", 2011L, complete = TRUE),
                 "provenance")
    expect_true(prov$completion$applied)
    expect_equal(prov$completion$absence_means$`2011`, "census_zero")
    expect_gt(prov$completion$rows_filled, 0L)

    off <- attr(cog_spending("121011212191", 2011L), "provenance")
    expect_false(off$completion$applied)
    expect_equal(off$completion$rows_filled, 0L)
  })
})

test_that("complete = TRUE is refused where the fill would be guesswork", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # A recipe defines its own component codes and does not go through
    # summary_categories at all, so there is no grid to fill from.
    expect_error(
      cog_spending("121011212191", 2011L, recipe = "corrections_combined",
                   complete = TRUE),
      class = "uscogdata_complete_unsupported"
    )
    # The intergovernmental leg keeps aggregate rows by design
    # (inst/sql/24-ig_long.sql), so its grid is not code_set's grid.
    expect_error(
      cog_spending("121011212191", 2011L, expenditure_concept = "total",
                   complete = TRUE),
      class = "uscogdata_complete_unsupported"
    )
  })
})

test_that("complete = TRUE aborts on a corpus with no representation contract", {
  skip_if_no_corpus()
  # A corpus published before sparsification carries neither table, so there
  # is nothing to fill from and no rule saying what an absence means. That
  # must abort rather than guess.
  with_corpus_missing_representation({
    expect_error(
      cog_spending("121011212191", 2011L, complete = TRUE),
      class = "uscogdata_representation_unavailable"
    )
    # ... while an ordinary query on the same corpus still works.
    expect_gt(nrow(cog_spending("121011212191", 2011L)), 0L)
  })
})
