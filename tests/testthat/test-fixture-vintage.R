# tests/testthat/test-fixture-vintage.R
#
# The bundled fixture is a slice of a real cog_pipeline publish tree, and
# every test in this package -- plus the whole cog-api suite -- runs against
# it. When the published corpus changes shape and the fixture does not, both
# suites stay green against a corpus that no longer exists (uscogdata#18).
#
# These tests pin the structural facts that distinguish the current published
# vintage from its predecessor, so a stale fixture fails loudly instead of
# passing quietly. They assert shape, never dollar values: re-running
# data-raw/regenerate_fixture_corpus.R against a newer publish tree should
# keep them green.

# Open a bare DuckDB connection on the fixture's parquet files. Deliberately
# not the package session: these assertions are about what the fixture
# CONTAINS, and routing them through the reader's own views would let a
# filter hide the very absence being checked.
fixture_query <- function(sql, ...) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  path <- function(rel) {
    sprintf("read_parquet(%s)",
            DBI::dbQuoteString(con, file.path(fixture_corpus_path(), rel)))
  }
  DBI::dbGetQuery(con, do.call(sprintf, c(list(sql), lapply(c(...), path))))
}

test_that("fixture ships every metadata table the publish tree does", {
  skip_if_no_corpus()
  # representation/code_set are what make a sparse corpus interpretable; a
  # fixture without them predates sparsification (cog_pipeline#64).
  expected <- c(
    "canonical_alias.parquet", "canonical_fips_xwalk.parquet",
    "census_collection_coverage.parquet", "code_set.parquet",
    "harmonization_map.parquet", "harmonization_recipes.parquet",
    "lineage_events.parquet", "representation.parquet",
    "series_breaks.parquet", "summary_categories.parquet"
  )
  on_disk <- basename(list.files(
    file.path(fixture_corpus_path(), "data"), pattern = "\\.parquet$"
  ))
  expect_true(all(expected %in% on_disk))

  # The manifest must list them too -- consumers read the manifest, not ls().
  in_manifest <- with_fixture_corpus(
    basename(vapply(cog_manifest()$files$metadata, function(f) f$path, character(1)))
  )
  expect_true(all(expected %in% in_manifest))
})

test_that("fixture carries the dense/sparse representation contract", {
  skip_if_no_corpus()
  rep <- fixture_query(
    "SELECT year, representation, absence_means FROM %s
     WHERE year IN (2011, 2012, 2019, 2020) ORDER BY year",
    "data/representation.parquet"
  )
  expect_equal(nrow(rep), 4L)
  expect_equal(rep$representation, c("dense_source", rep("sparse_source", 3L)))
  expect_equal(rep$absence_means, c("census_zero", rep("not_reported", 3L)))
})

test_that("the fixture's wide era is sparse, not zero-padded", {
  skip_if_no_corpus()
  # FY2011 is a dense_source year: the corpus publishes only the cells Census
  # reported non-zero, and an absent cell means Census published $0. Before
  # sparsification this partition was 2,864,212 rows, ~83% of them explicit
  # zeros. A single explicit zero here means the fixture predates the change.
  zeros_2011 <- fixture_query(
    "SELECT COUNT(*) AS n FROM %s WHERE amt = 0",
    "data/long/year=2011/part-0.parquet"
  )$n
  expect_equal(zeros_2011, 0L)

  # The modern era is a different regime: a reported zero there is real data
  # (the government filed $0), so zeros legitimately survive and must not be
  # asserted away.
  expect_gt(
    fixture_query("SELECT COUNT(*) AS n FROM %s", "data/long/year=2012/part-0.parquet")$n,
    0L
  )
})

test_that("code_set covers every fixture year with the reader-spec columns", {
  skip_if_no_corpus()
  cs <- fixture_query(
    "SELECT * FROM %s WHERE year IN (2011, 2012, 2019, 2020)",
    "data/code_set.parquet"
  )
  expect_true(all(
    c("code_set_id", "year", "type", "item_code", "is_aggregate", "n_units")
    %in% names(cs)
  ))
  expect_setequal(unique(cs$year), c(2011L, 2012L, 2019L, 2020L))
})

test_that("every flow code carrying dollars has a category, J-prefix included", {
  skip_if_no_corpus()
  # The J (assistance/benefit) codes were uncategorised until the crosswalk
  # completion shipped (cog_pipeline#60/#65, J19 held back until #64's
  # duplication fix landed). Their absence is how a pre-crosswalk fixture
  # gives itself away.
  j <- fixture_query(
    "SELECT item_code, category, category_type, spend_subtype FROM %s
     WHERE LEFT(item_code, 1) = 'J' ORDER BY item_code",
    "data/summary_categories.parquet"
  )
  expect_true("J19" %in% j$item_code)
  expect_true(all(j$category_type == "expenditure"))
  expect_true(all(j$spend_subtype == "assistance"))
  expect_false(any(is.na(j$category)))
})
