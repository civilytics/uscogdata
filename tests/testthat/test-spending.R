test_that("cog_spending returns expected shape for Broward Corrections 2020", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", years = 2020L, category = "Corrections")
  expect_s3_class(r, "tbl_df")
  expected_cols <- c("year", "canonical_govid", "gov_name", "spend_subtype",
                     "category", "amt_nominal", "codes_included",
                     "aggregate_fallback", "notes")
  expect_true(all(expected_cols %in% names(r)))
  expect_equal(unique(r$canonical_govid), "121011212191")
  expect_equal(unique(r$year), 2020L)
  expect_equal(unique(r$category), "Corrections")
  expect_true(all(r$spend_subtype %in% c("operations", "capital")))
  expect_true(all(r$amt_nominal > 0))
})

test_that("cog_spending vectorised years + categories", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2019:2020,
                    category = c("Corrections", "Police"))
  expect_true(all(r$year %in% 2019:2020))
  expect_true(all(r$category %in% c("Corrections", "Police")))
  expect_gte(nrow(r), 4L)
})

test_that("cog_spending with per_capita adds per-capita nominal column", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections", per_capita = TRUE)
  expect_true("amt_per_capita_nominal" %in% names(r))
  expect_false("amt_real" %in% names(r))
  expect_false("amt_per_capita_real" %in% names(r))
  expect_true(all(is.finite(r$amt_per_capita_nominal)))
  expect_true(all(r$amt_per_capita_nominal < r$amt_nominal))
})

test_that("cog_spending with adjust_to_year adds real column", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2019:2020, "Corrections",
                    adjust_to_year = 2022L)
  expect_true("amt_real" %in% names(r))
  r2019 <- dplyr::filter(r, year == 2019L)
  expect_true(any(r2019$amt_nominal != r2019$amt_real))
})

test_that("cog_spending with per_capita + adjust_to_year adds all columns", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections",
                    per_capita = TRUE, adjust_to_year = 2022L)
  expect_true(all(c("amt_nominal", "amt_real",
                    "amt_per_capita_nominal", "amt_per_capita_real") %in%
                  names(r)))
})

test_that("cog_spending for unknown govid returns empty tibble + informs", {
  skip_if_no_corpus()
  expect_message(
    r <- cog_spending("XXXINVALID", 2020L, "Corrections"),
    "not found|v0.1"
  )
  expect_s3_class(r, "tbl_df")
  expect_equal(nrow(r), 0L)
  expect_true("notes" %in% names(r))
  prov <- attr(r, "provenance")
  expect_false(is.null(prov))
  expect_equal(prov$scope$govids_missing, "XXXINVALID")
  expect_equal(length(prov$scope$govids_found), 0L)
})

test_that("cog_spending records found + missing govids in provenance", {
  skip_if_no_corpus()
  suppressMessages(
    r <- cog_spending(c("121011212191", "XXXINVALID"), 2020L, "Corrections")
  )
  prov <- attr(r, "provenance")
  expect_equal(sort(prov$scope$govids_found), "121011212191")
  expect_equal(sort(prov$scope$govids_missing), "XXXINVALID")
})

test_that("cog_spending result has provenance attribute matching schema", {
  skip_if_no_corpus()
  r <- cog_spending("121011212191", 2020L, "Corrections")
  prov <- attr(r, "provenance")
  expect_type(prov, "list")
  expect_equal(prov$verb, "cog_spending")
  required <- c("verb", "target", "years", "scope", "manifest", "sql_query")
  expect_true(all(required %in% names(prov)))
  expect_equal(prov$years, 2020L)
  expect_equal(prov$category, "Corrections")
  expect_type(prov$sql_query, "character")
  expect_true(grepl("spending_annotated", prov$sql_query))
  expect_type(prov$codes_summed$observed, "character")
  expect_true(all(c("E04") %in% prov$codes_summed$observed))
})

test_that("cog_spending rejects invalid inputs", {
  expect_error(cog_spending(list(), 2020L), "character|data frame")
  expect_error(cog_spending("121011212191", "2020"), "years")
})

test_that("cog_spending accepts a cog_gov_search result directly", {
  skip_if_no_corpus()
  picks <- cog_gov_search("^BROWARD COUNTY$", state = "FL", type = "county")
  expect_gt(nrow(picks), 0L)
  r <- cog_spending(picks, 2020L, "Corrections")
  expect_equal(unique(r$canonical_govid), "121011212191")
})

test_that("cog_spending accepts a cog_find_peers result directly", {
  skip_if_no_corpus()
  peers <- cog_find_peers("121011212191", max_peers = 3L)
  r <- cog_spending(peers, 2020L, "Police")
  expect_setequal(unique(r$canonical_govid),
                  sort(peers$canonical_govid))
})

test_that("cog_spending rejects data.frame without canonical_govid column", {
  bad <- tibble::tibble(foo = "bar")
  expect_error(cog_spending(bad, 2020L), "canonical_govid")
})

test_that("cog_spending accepts a basket-mode cog_gov_search result", {
  skip_if_no_corpus()
  basket <- cog_gov_search(
    name  = c("BROWARD COUNTY", "SAN DIEGO COUNTY"),
    state = c("FL",             "CA")
  )
  expect_equal(nrow(basket), 2L)
  spending <- cog_spending(basket, years = 2019:2020, category = "Police")
  expect_s3_class(spending, "tbl_df")
  expect_setequal(unique(spending$canonical_govid), basket$canonical_govid)
})

test_that("per_capita denominator is the per-year F-33 population", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", years = 2019:2020,
                      category = "Police", per_capita = TRUE)
    r_ops <- r[r$spend_subtype == "operations", ]
    # Implied denominator from amt_nominal / amt_per_capita_nominal
    implied_pop <- r_ops$amt_nominal / r_ops$amt_per_capita_nominal
    names(implied_pop) <- r_ops$year
    # Use absolute tolerance: within 1 person of per-year F-33 values.
    # Hardcoded values are Broward County's per-year Census F-33 population
    # from the bundled fixture (regenerated 2026-07-11 against cog_pipeline
    # publish tree, pipeline_commit 1a00925, Phase P schema_version 4).
    # 1,940,907 is the static ACS 2018-2022 5-year value the legacy
    # implementation would use; we assert it is NOT what we get.
    expect_true(abs(implied_pop[["2019"]] - 1935878) < 1)
    expect_true(abs(implied_pop[["2020"]] - 1952778) < 1)
    expect_false(all(abs(implied_pop - 1940907) < 1))
  })
})

test_that("pop_source = 'census_f33' does not produce unavailable-pop note", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", years = 2019L,
                      category = "Police", per_capita = TRUE)
    expect_true(all(r$pop_source == "census_f33"))
    expect_true(all(is.na(r$notes) | r$notes == "" |
                    !grepl("No population denominator", r$notes)))
  })
})

test_that("aggregate fallback + unavailable pop produce concatenated notes", {
  # Unit-level test of .notes_column with a synthetic data frame so we don't
  # depend on having a type-4/5 gov in the fixture.
  result <- tibble::tibble(
    aggregate_fallback = c(FALSE, TRUE,  TRUE),
    pop_source         = c("census_f33", "census_f33", "unavailable")
  )
  notes <- uscogdata:::.notes_column(result)
  expect_equal(notes[1], "")
  expect_equal(notes[2], "Aggregate fallback applied; see cog_explain()")
  expect_equal(notes[3],
               "Aggregate fallback applied; see cog_explain(); No population denominator available for this gov type")
})

test_that("provenance records per-year denominator metadata", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", years = 2019:2020,
                      category = "Police", per_capita = TRUE)
    pc <- attr(r, "provenance")$transformations$per_capita
    expect_true(pc$applied)
    expect_match(pc$denominator_source, "Census F-33", fixed = FALSE)
    expect_match(pc$denominator_source, "per-year", fixed = TRUE)
    expect_equal(pc$pop_source_counts$census_f33, nrow(r))
    expect_equal(pc$pop_source_counts$unavailable, 0L)
    expect_equal(length(pc$popyear_range), 2L)
  })
})

# --- basis = "harmonized" / "raw" (Phase R2, schema v5) --------------------

test_that("basis = 'raw' reproduces the pre-harmonization Broward Police totals", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", years = 2019:2020, category = "Police",
                      basis = "raw")
    # Regression pin captured against the schema v5 fixture (2026-07-18,
    # pipeline_commit ece9b32) before basis = "harmonized" existed as a
    # concept; these are the same totals the pre-Phase-R2 default query
    # returned (spending_annotated is untouched by the harmonized views).
    ops <- r$amt_nominal[r$year == 2019L & r$spend_subtype == "operations"]
    cap <- r$amt_nominal[r$year == 2020L & r$spend_subtype == "capital"]
    expect_equal(ops, 483560000)
    expect_equal(cap, 26693000)
    expect_equal(attr(r, "provenance")$basis, "raw")
  })
})

test_that("basis = 'harmonized' (default) matches 'raw' when no harmonization rule applies", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # Every `method = "collapse"` mapping in the curated harmonization_map
    # ends by FY2004 for codes inside the spending/revenue flow-type
    # prefixes (E/F/G/K, T/A/U/B/C/D); the one collapse extending to FY2011
    # (L38/M38 -> L36/M36) is intergovernmental-transfer (L/M prefix) codes
    # that were never part of spending_long/revenue_long to begin with. So
    # for the fixture's 2011-2020 window, basis = "harmonized" is a
    # data-verified no-op vs "raw" for in-scope codes -- this is the
    # positive-control counterpart to the synthetic REPLACE-mechanism test
    # in test-views.R, which proves the fold itself works when data exists.
    r_raw  <- cog_spending("121011212191", c(2011L, 2012L, 2019L, 2020L),
                           "Police", basis = "raw")
    r_harm <- cog_spending("121011212191", c(2011L, 2012L, 2019L, 2020L),
                           "Police", basis = "harmonized")
    expect_equal(attr(r_harm, "provenance")$basis, "harmonized")
    expect_equal(
      r_harm$amt_nominal[order(r_harm$year, r_harm$spend_subtype)],
      r_raw$amt_nominal[order(r_raw$year, r_raw$spend_subtype)]
    )
  })
})

test_that("basis defaults to 'harmonized' when not passed", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", 2020L, "Police")
    expect_equal(attr(r, "provenance")$basis, "harmonized")
  })
})

test_that("provenance carries basis + harmonization block with na_rows_excluded", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", 2011:2012, "Corrections")
    prov <- attr(r, "provenance")
    expect_equal(prov$basis, "harmonized")
    expect_true(prov$harmonization$applied)
    expect_true(prov$harmonization$na_rows_excluded >= 0L)
    expect_true(prov$harmonization$na_amount_excluded >= 0)
    # Data-verified for this fixture: none of the discontinued_na rulings
    # (S74, Z61, X04, X06, the debt-detail family, L24) fall inside the
    # E/F/G/K spending prefixes, so the exclusion count is exactly zero for
    # every year in the bundled window -- see
    # docs/phase_r_harmonization_review.md § 1.3/1.4.
    expect_equal(prov$harmonization$na_rows_excluded, 0L)
    expect_equal(prov$harmonization$na_amount_excluded, 0)
  })
})

test_that("basis = 'raw' never populates the harmonization exclusion block", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", 2020L, "Corrections", basis = "raw")
    h <- attr(r, "provenance")$harmonization
    expect_false(h$applied)
    expect_equal(h$na_rows_excluded, 0L)
  })
})

test_that("v4 corpus: basis silently resolves to raw (default) with a provenance note", {
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    r <- cog_spending("121011212191", 2019L, "Police")
    prov <- attr(r, "provenance")
    expect_equal(prov$basis, "raw")
    expect_match(prov$basis_note, "raw", fixed = TRUE)
    expect_match(prov$basis_note, "schema_version", fixed = TRUE)
    expect_false(prov$harmonization$applied)
  })
})

test_that("v4 corpus: explicit basis = 'harmonized' aborts", {
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    expect_error(
      cog_spending("121011212191", 2019L, "Police", basis = "harmonized"),
      class = "uscogdata_basis_unsupported"
    )
  })
})

test_that("v4 corpus: explicit basis = 'raw' still works", {
  skip_if_no_corpus()
  with_doctored_schema_version(4L, {
    r <- cog_spending("121011212191", 2019L, "Police", basis = "raw")
    expect_equal(attr(r, "provenance")$basis, "raw")
    expect_gt(nrow(r), 0L)
  })
})
