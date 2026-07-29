# Madison walkthrough audit -- finding F-014. Tracked as uscogdata#12.
# See docs/walkthroughs/FINDINGS.md in cog_explorer.
#
# cog_revenue()'s flow_prefixes = c("T","A","U","B","C","D") never returns
# item-code prefix X (Employee Retirement) or Y (other Insurance Trust). Per
# Census's standard identity, Total Revenue = General + Utility + Liquor Store +
# Insurance Trust Revenue, and Employee Retirement System contributions and
# earnings ARE the Insurance Trust Revenue component -- so prefix X sits inside
# a published Census revenue concept exactly the way I89 sits inside Census's
# Direct Expenditure concept (finding F-012).
#
# CAVEAT FOR WHOEVER PICKS THIS UP: the argument name below (`revenue_concept =
# "total"`) is this test's *proposal*, not a settled decision. The owner's
# 2026-07-28 resolution covers expenditure concepts only; no revenue-side
# naming has been ruled on. If the eventual argument is named differently,
# change the two calls here -- the asserted dollar invariants are what matter
# and are independent of the naming.
#
# Fixture reproducibility: Madison's own X-prefix revenue (FY1970-FY1986,
# $15,098,000 nominal, $0 thereafter) is outside the bundled fixture's year
# window (2011/2012/2019/2020), so the same invariant is asserted on Wisconsin
# state government FY2012, where the fixture carries nonzero X01/X05/X08.

test_that("cog_revenue() can return Census Total Revenue including Insurance Trust (prefix X)", {
  testthat::skip("Blocked on uscogdata#12 (finding F-014)")

  wi_state <- "550000227544"   # WISCONSIN (state government)

  # Revenue-shaped Employee Retirement codes, read from the RAW corpus rather
  # than through cog_revenue(), which is the filter under test:
  #   X01 local employee contribution, X04/X05 contributions and transfers from
  #   other governments, X08 earnings on investments.
  x_revenue <- wt_raw_amt(wi_state, 2012L, codes = c("X01", "X04", "X05", "X08"))
  expect_equal(x_revenue, 2038800)   # 615,835 + 0 + 560,382 + 862,583 ($1,000s)

  general <- cog_revenue(govid = wi_state, years = 2012L)
  expect_equal(sum(general$amt_nominal), 31338293000)

  total <- cog_revenue(govid = wi_state, years = 2012L, revenue_concept = "total")
  expect_equal(sum(total$amt_nominal) - sum(general$amt_nominal), x_revenue * 1000)
  expect_equal(sum(total$amt_nominal), 33377093000)
  expect_true(all(c("X01", "X05", "X08") %in% wt_codes_included(total)))

  # Sibling codes under the SAME first letter must stay out: X11/X12 are
  # benefit payments (an expenditure) and X21/X30/X47 are cash and securities
  # holdings (a balance-sheet stock). This is the F-018 point restated on the
  # revenue side -- the split has to come from the crosswalk's spend_type, not
  # from the letter X.
  expect_false(any(c("X11", "X12", "X21", "X30", "X47") %in% wt_codes_included(total)))

  # Every returned row still resolves to a category. summary_categories has
  # zero rows for prefix X today, so relaxing the prefix filter alone would
  # produce category = NA rows -- see census_of_governments_finance_pipeline#60.
  expect_false(any(is.na(total$category)))
})
