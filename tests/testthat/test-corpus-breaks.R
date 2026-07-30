# tests/testthat/test-corpus-breaks.R
#
# uscogdata#19. Four catalogued series breaks carry fin_code = "ALL" -- they
# are caveats about the corpus itself rather than about one item code:
#
#   SB085  1977  dollar precision across the 1976/1977 boundary
#   SB087  2002  imputation exclusion FY2002-2006
#   SB194  2012  dense -> sparse representation change
#   SB086  2017  government ID scheme change
#
# .build_series_break_refs() matches `fin_code IN (<codes in the result>)`,
# and no row's item_code is ever the literal "ALL", so none of them could
# ever reach a user. They now travel in their own provenance field,
# `corpus_break_refs`, which keeps them distinguishable from the
# code-specific `series_break_refs` (an ALL caveat qualifies the whole
# result, not one series).

test_that("corpus_break_refs surfaces an ALL-scoped break the year range spans", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # SB194 sits at FY2012 -- the dense/sparse boundary. A query spanning
    # 2011 -> 2012 straddles it, and this is the case cog_pipeline#64's
    # DoD 4 intended to reach users.
    r <- cog_spending("121011212191", 2011:2012, "Police")
    prov <- attr(r, "provenance")
    expect_true("SB194" %in% prov$corpus_break_refs)
  })
})

test_that("corpus_break_refs stays empty when no ALL break falls in the range", {
  skip_if_no_corpus()
  with_fixture_corpus({
    # 2019-2020 spans no catalogued corpus-wide break.
    r <- cog_spending("121011212191", 2019:2020, "Police")
    expect_equal(attr(r, "provenance")$corpus_break_refs, character(0))
  })
})

test_that("corpus_break_refs and series_break_refs stay disjoint", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", 2011:2012, "Police")
    prov <- attr(r, "provenance")
    expect_type(prov$series_break_refs, "character")
    expect_type(prov$corpus_break_refs, "character")
    # An ALL caveat must never masquerade as a break in a specific series.
    expect_length(intersect(prov$series_break_refs, prov$corpus_break_refs), 0L)
    expect_false("SB194" %in% prov$series_break_refs)
  })
})

test_that(".build_corpus_break_refs matches on the break_year window alone", {
  skip_if_no_corpus()
  con <- cog_open()
  on.exit(cog_close())

  # SB085's boundary is 1976/1977, outside the fixture's partitions -- the
  # series_breaks table is a full cross-vintage registry, so the matching
  # logic is testable there even though no long partition covers it.
  expect_true("SB085" %in% uscogdata:::.build_corpus_break_refs(
    con, years = 1975:1980, schema_version = 6L
  ))
  # ... and does not fire for a range that misses it, unlike a filter keyed
  # on the era rather than the boundary.
  expect_false("SB085" %in% uscogdata:::.build_corpus_break_refs(
    con, years = 1978:1980, schema_version = 6L
  ))

  # Unlike code-specific refs, these do not depend on which codes a result
  # happens to contain -- that dependency is the whole defect.
  expect_setequal(
    uscogdata:::.build_corpus_break_refs(con, years = 2001:2003, schema_version = 6L),
    "SB087"
  )

  # Gated on schema_version >= 5: series_breaks_pq is not registered below it.
  expect_equal(
    uscogdata:::.build_corpus_break_refs(con, years = 2011:2012, schema_version = 4L),
    character(0)
  )
})

test_that("cog_explain() prints corpus-wide caveats under their own heading", {
  skip_if_no_corpus()
  with_fixture_corpus({
    r <- cog_spending("121011212191", 2011:2012, "Police")
    out <- paste(c(
      capture.output(cog_explain(r)),
      capture.output(cog_explain(r), type = "message")
    ), collapse = "\n")
    expect_match(out, "Corpus-wide caveats", fixed = TRUE)
    expect_match(out, "SB194", fixed = TRUE)
  })
})
