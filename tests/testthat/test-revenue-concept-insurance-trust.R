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
# RULED 2026-07-30. `revenue_concept = c("general", "total")` mirrors
# `expenditure_concept`, and the two values are Census's two published revenue
# concepts, related by the manual's own identity (section 4.3, which defines
# the first by SUBTRACTING from the second):
#
#   Total Revenue = General + Utility + Liquor Store + Insurance Trust
#
# so `general` is the four general subtypes (own_source/federal/state/
# local_aid) and `total` is every revenue subtype. Naming utility (A91-A94)
# and liquor store (A90) separately is what makes BOTH computable -- before
# cog_pipeline#79 they sat in own_source, so the default was really
# "General + Utility + Liquor", a concept Census does not publish.
#
# Fixture reproducibility: Madison's own X-prefix revenue (FY1970-FY1986,
# $15,098,000 nominal, $0 thereafter) is outside the bundled fixture's year
# window (2011/2012/2019/2020), so the same invariant is asserted on Wisconsin
# state government FY2012, where the fixture carries nonzero X01/X02/X05/X08.

test_that("cog_revenue() can return Census Total Revenue including Insurance Trust (prefix X)", {
  wi_state <- "550000227544"   # WISCONSIN (state government)

  # Revenue-shaped Employee Retirement codes, read from the RAW corpus rather
  # than through cog_revenue(), which is the filter under test:
  #   X01/X02 employee contributions, X05 contributions from other governments,
  #   X08 total earnings on investments.
  #
  # X04 and X06 are deliberately NOT in this set, though an earlier draft of
  # this test included X04. Both are exhibit codes for INTRAgovernmental
  # transfers (the administering government paying into its own fund), which
  # X05's own definition excludes by name. Census agrees: its computed "Total
  # Emp Ret Rev" for this government-year is exactly the four codes below.
  x_revenue <- wt_raw_amt(wi_state, 2012L, codes = c("X01", "X02", "X05", "X08"))
  expect_equal(x_revenue, 2283883)   # 615,835 + 245,083 + 560,382 + 862,583

  # The Y-prefix insurance trust revenue (unemployment + workers comp), which
  # is the other half of the same Census concept.
  y_revenue <- wt_raw_amt(wi_state, 2012L, codes = c("Y01", "Y11"))
  expect_equal(y_revenue, 1259785)

  general <- cog_revenue(govid = wi_state, years = 2012L)
  expect_equal(attr(general, "provenance")$revenue_concept, "general")
  expect_equal(sum(general$amt_nominal), 31338293000)

  total <- cog_revenue(govid = wi_state, years = 2012L, revenue_concept = "total")
  expect_equal(attr(total, "provenance")$revenue_concept, "total")

  # total - general is the whole insurance trust leg, X and Y together.
  # Asserted as a delta as well as a level so this stays correct however the
  # utility/liquor families land (both are $0 for WI state in FY2012).
  expect_equal(sum(total$amt_nominal) - sum(general$amt_nominal),
               (x_revenue + y_revenue) * 1000)
  expect_equal(sum(total$amt_nominal), 34881961000)
  expect_true(all(c("X01", "X02", "X05", "X08") %in% wt_codes_included(total)))

  # Sibling codes under the SAME first letter must stay out: X11/X12 are
  # benefit payments (an expenditure) and X21/X30/X47 are cash and securities
  # holdings (a balance-sheet stock). This is the F-018 point restated on the
  # revenue side -- the split comes from the crosswalk, not from the letter X.
  expect_false(any(c("X11", "X12", "X21", "X30", "X47") %in% wt_codes_included(total)))

  # Every returned row still resolves to a category (cog_pipeline#79 added the
  # X crosswalk rows; relaxing a prefix filter alone would have produced
  # category = NA rows).
  expect_false(any(is.na(total$category)))
})

test_that("revenue_concept = 'general' is the default and is strict Census General Revenue", {
  wi_state <- "550000227544"
  default  <- cog_revenue(govid = wi_state, years = 2012L)
  explicit <- cog_revenue(govid = wi_state, years = 2012L,
                          revenue_concept = "general")
  expect_equal(sum(default$amt_nominal), sum(explicit$amt_nominal))

  # General Revenue excludes utility, liquor store AND insurance trust
  # revenue. WI state carries $0 of utility/liquor in FY2012, so the level
  # assertion above cannot see those two -- assert the subtype scope directly.
  #
  # A subset, not setequal: `state` means "intergovernmental revenue FROM the
  # state government" (the C codes), which a STATE government does not receive
  # from itself, so it is legitimately absent here.
  expect_true(all(default$revenue_subtype %in%
                    c("own_source", "federal", "state", "local_aid")))
  expect_false(any(c("utility", "liquor_store", "insurance_trust") %in%
                     default$revenue_subtype))
})

test_that("utility and liquor store revenue are inside `total` and outside `general`", {
  # A city, where utility revenue is material: this is the case the WI state
  # baseline structurally cannot exercise. Measured on the fixture, utility +
  # liquor is 15.9% of what cog_revenue() returned for type-2 governments
  # before the general/total split, so this is the largest behaviour change
  # the concept split introduces.
  con <- uscogdata:::.ensure_session()
  gov <- DBI::dbGetQuery(con,
    "SELECT canonical_govid, SUM(amt) amt FROM long
     WHERE year = 2012 AND type = 2 AND NOT is_aggregate
       AND item_code IN ('A91','A92','A93','A94')
     GROUP BY 1 ORDER BY amt DESC LIMIT 1")$canonical_govid

  util_raw <- wt_raw_amt(gov, 2012L, codes = c("A90", "A91", "A92", "A93", "A94"))
  expect_gt(util_raw, 0)

  general <- cog_revenue(govid = gov, years = 2012L)
  total   <- cog_revenue(govid = gov, years = 2012L, revenue_concept = "total")

  expect_false(any(c("utility", "liquor_store") %in% general$revenue_subtype))
  expect_true("utility" %in% total$revenue_subtype)
  expect_equal(sum(total$amt_nominal) - sum(general$amt_nominal),
               util_raw * 1000 +
                 wt_raw_amt(gov, 2012L, codes = c("Y01", "Y11", "X01", "X02",
                                                   "X05", "X08")) * 1000)
})

test_that("revenue_concept rejects unknown values and never returns a balance row", {
  expect_error(
    cog_revenue("550000227544", years = 2012L, revenue_concept = "gross"),
    class = "uscogdata_invalid_revenue_concept"
  )

  # uscogdata#25 restated for the widest revenue concept: stocks are not
  # flows, and `total` must not quietly admit the X/Y/W/Z balance families.
  con <- uscogdata:::.ensure_session()
  balance <- DBI::dbGetQuery(con,
    "SELECT item_code, category FROM summary_categories WHERE category_type = 'balance'")
  total <- cog_revenue("550000227544", years = 2012L, revenue_concept = "total")
  expect_false(any(total$category %in% balance$category))
  expect_length(intersect(wt_codes_included(total), balance$item_code), 0L)
})
