# Madison walkthrough audit -- findings F-012, F-017, F-018.
# Tracked as uscogdata#11. See docs/walkthroughs/FINDINGS.md in cog_explorer.
#
# The owner's settled three-concept model (2026-07-28):
#   total   = primary + interest + intergovernmental transfers
#   direct  = primary + interest          (Census's published Direct Expenditure)
#   primary = direct minus debt service   (the NEW DEFAULT)
# implemented by reclassifying on the crosswalk's `spend_type` column, NOT on
# item-code first letters -- F-018 shows prefix `Y` carries both revenue
# (Y01/Y02) and expenditure (Y05/Y06) codes, so no first-letter allowlist can
# route them correctly.
#
# Fixture reproducibility: the finding's headline reconciliation is Madison
# FY2022, where the corpus carries I89 = 46,609 (thousands) and Census's
# published Direct Expenditure is $654,893,000 against cog_spending()'s
# $608,284,000 (-7.1%). FY2022 is outside the bundled fixture's year window
# (2011/2012/2019/2020), so the same invariant is asserted on FY2020, where the
# fixture carries I89 = 27,704. Anyone running against the full corpus should
# also check the FY2022 numbers above.

test_that("expenditure concepts classify on spend_type, not item-code prefix", {
  testthat::skip("Blocked on uscogdata#11 (findings F-012, F-017, F-018)")

  mad      <- "552025209777"   # MADISON CITY, WI
  wi_state <- "550000227544"   # WISCONSIN (state government)

  # -- F-012: `primary` is the new default, and equals today's E/F/G figure ---
  primary <- cog_spending(govid = mad, years = 2020L)
  expect_equal(attr(primary, "provenance")$expenditure_concept, "primary")
  expect_equal(sum(primary$amt_nominal), 623347000)

  # -- F-012: `direct` adds interest on long-term debt ------------------------
  # Expected interest read from the RAW corpus, never through cog_spending(),
  # which is the filter under test.
  interest <- wt_raw_amt(mad, 2020L, prefixes = "I")
  expect_equal(interest, 27704)                       # I89, in $1,000s

  direct <- cog_spending(govid = mad, years = 2020L, expenditure_concept = "direct")
  expect_equal(sum(direct$amt_nominal), 651051000)    # 623,347 + 27,704 thousands
  expect_equal(sum(direct$amt_nominal) - sum(primary$amt_nominal), interest * 1000)
  expect_true("I89" %in% wt_codes_included(direct))

  # -- F-017: `total` carries Q12/Q18, state IG transfers to school districts --
  # Wisconsin FY2019: Q12 = 6,431,530 and Q18 = 533,391 (thousands). Today
  # neither verb's flow_prefixes contains "Q", so both are dropped from the one
  # concept that is supposed to include intergovernmental transfers.
  ig_expected <- wt_raw_amt(wi_state, 2019L, prefixes = c("M", "L", "Q"))
  expect_equal(ig_expected, 11609814)                 # M 4,644,893 + Q 6,964,921

  wi_direct <- cog_spending(govid = wi_state, years = 2019L,
                            expenditure_concept = "direct")
  wi_total  <- cog_spending(govid = wi_state, years = 2019L,
                            expenditure_concept = "total")

  # total - direct is exactly the intergovernmental component. Asserted as a
  # delta rather than a grand total so this stays correct however the J and Y
  # families land inside `primary`.
  expect_equal(sum(wi_total$amt_nominal) - sum(wi_direct$amt_nominal),
               ig_expected * 1000)
  expect_true(all(c("Q12", "Q18") %in% wt_codes_included(wi_total)))

  # -- F-018: prefix Y splits revenue from expenditure, by spend_type ---------
  # Y01/Y02 are Insurance Trust revenue; Y05/Y06 are Insurance Trust benefit
  # payments. All four share the first letter `Y` and the spend_type
  # "Insurance Trust", so this pair of assertions is the concrete proof that
  # classification is no longer keyed on the first letter.
  wi_revenue <- cog_revenue(govid = wi_state, years = 2019L)
  spend_codes <- wt_codes_included(wi_total)
  rev_codes   <- wt_codes_included(wi_revenue)

  expect_true("Y05" %in% spend_codes)
  expect_false("Y05" %in% rev_codes)
  expect_true("Y01" %in% rev_codes)
  expect_false("Y01" %in% spend_codes)
})
