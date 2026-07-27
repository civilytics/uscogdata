test_that("the corpus contains no K-prefix rows, so the Direct leg omits K", {
  con <- .ensure_session()
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM long WHERE LEFT(item_code, 1) = 'K'")$n
  expect_equal(n, 0)

  sql_files <- c("20-spending_long.sql", "22-spending_long_harmonized.sql")
  for (f in sql_files) {
    txt <- paste(readLines(system.file("sql", f, package = "uscogdata")),
                 collapse = " ")
    expect_false(grepl("'K'", txt, fixed = TRUE),
                 label = paste(f, "must not reference the inert K prefix"))
  }
})

test_that("expenditure_concept defaults to direct and preserves today's numbers", {
  gov <- "010000226085"                      # Alabama state government
  base <- cog_spending(gov, years = 2019, category = "Police")
  expl <- cog_spending(gov, years = 2019, category = "Police",
                       expenditure_concept = "direct")
  expect_equal(base$amt_nominal, expl$amt_nominal)
  expect_false("intergovernmental" %in% base$spend_subtype)
})

test_that("expenditure_concept = 'total' adds an intergovernmental subtype", {
  gov <- "010000226085"
  d <- cog_spending(gov, years = 2019, category = "Police",
                    expenditure_concept = "direct")
  t <- cog_spending(gov, years = 2019, category = "Police",
                    expenditure_concept = "total")
  expect_true("intergovernmental" %in% t$spend_subtype)
  # Direct rows are untouched; Total only ever ADDS. Use %in% rather than
  # != : a category = NULL result can contain a NULL-subtype group (codes
  # with no summary_categories row, e.g. E16/E21/E85/F16/F85/G16/G21/G85),
  # and `NA != "intergovernmental"` is NA, not TRUE, which would silently
  # smuggle an all-NA phantom row into dt.
  dt <- t[!(t$spend_subtype %in% "intergovernmental"), ]
  expect_equal(sort(dt$amt_nominal), sort(d$amt_nominal))
  expect_gt(sum(t$amt_nominal), sum(d$amt_nominal))
})

test_that("legacy-era Total does not collapse to Direct (the is_aggregate trap)", {
  # In the wide era the IG dollars live almost entirely on aggregate-flagged
  # rows. A Total leg that inherited the Direct leg's NOT is_aggregate filter
  # would silently return Total == Direct here.
  gov <- "010000226085"
  d <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "direct")
  t <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total")
  expect_true("intergovernmental" %in% t$spend_subtype)
  ig <- sum(t$amt_nominal[t$spend_subtype == "intergovernmental"])
  expect_gt(ig, 0)
  expect_gt(sum(t$amt_nominal), sum(d$amt_nominal))
})

test_that("the IG leg never includes the L-- family total", {
  con <- .ensure_session()
  codes <- DBI::dbGetQuery(con,
    "SELECT DISTINCT item_code FROM ig_long")$item_code
  expect_false(any(grepl("--$", codes)))
  expect_true(all(substr(codes, 1, 1) %in% c("M", "L")))
})

test_that("expenditure_concept rejects unknown values", {
  expect_error(
    cog_spending("010000226085", years = 2019, expenditure_concept = "gross"),
    class = "rlang_error"
  )
})

test_that("total composes with basis = 'raw' and basis = 'harmonized'", {
  gov <- "010000226085"
  h <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total", basis = "harmonized")
  r <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total", basis = "raw")
  ig_h <- sum(h$amt_nominal[h$spend_subtype == "intergovernmental"])
  ig_r <- sum(r$amt_nominal[r$spend_subtype == "intergovernmental"])
  # The only IG harmonization rule is M38 -> M36 (year-disjoint), so the IG
  # total must agree between bases even though the code labels may differ.
  expect_equal(ig_h, ig_r)
})

test_that("recipe = and expenditure_concept = 'total' together aborts", {
  expect_error(
    cog_spending("121011212191", 2020L, recipe = "corrections_combined",
                expenditure_concept = "total"),
    class = "uscogdata_recipe_concept_conflict"
  )
})

test_that("aggregate-sourced IG dollars are flagged aggregate_fallback = TRUE (bool_or, not bool_and)", {
  # Regression test: .build_verb_sql() originally used bool_and(is_aggregate)
  # for aggregate_fallback, which is correct for the Direct leg (a group can
  # never mix aggregate and non-aggregate rows there -- spending_long filters
  # NOT is_aggregate) but wrong for the IG leg. The wide era is dense -- every
  # government has a $0 row for every code in a family -- so a $0 leaf sits in
  # the same (year, gov, subtype, category) group as the real aggregate row
  # and flips bool_and() to FALSE. Measured: AL state 2011 had $5,740,775,000
  # of aggregate-sourced IG dollars (Corrections $31,358,000 + Education K-12
  # $5,152,385,000 + General Government $557,032,000) reporting
  # aggregate_fallback = FALSE under bool_and(), with the only TRUE row being
  # Transit Utilities at $0. bool_or() reports all of them correctly.
  gov <- "010000226085"
  t <- cog_spending(gov, years = 2011, category = "Education K-12",
                    expenditure_concept = "total")
  ig <- t[t$spend_subtype == "intergovernmental", ]
  expect_equal(nrow(ig), 1L)
  expect_true(ig$aggregate_fallback)
  expect_true(nzchar(ig$notes))
  expect_match(ig$notes, "Aggregate fallback applied", fixed = TRUE)
})

test_that("legacy aggregate IG codes are year-disjoint from their modern leaf components", {
  # The safety of ig_long's deliberate omission of `NOT is_aggregate` (see
  # inst/sql/24-ig_long.sql) rests entirely on each legacy code's AGGREGATE
  # instance being year-disjoint from the modern leaf codes it rolls up --
  # if a future corpus rebuild ever back-filled a leaf into a year where the
  # code is still flagged aggregate, `total` would silently double-count and
  # this suite would still pass. This test fails loudly if that ever
  # happens.
  #
  # Note the invariant is scoped to the AGGREGATE flag, not bare code
  # presence: M89/L89 do NOT disappear after the wide era the way M47/L47
  # do -- they continue past 2011 as their OWN independent leaf line item
  # (is_aggregate = FALSE) alongside M91-93/L91-93, which is fine because a
  # non-aggregate M89/L89 no longer represents a rollup of those codes.
  # (Verified in the fixture: M89/L89 are is_aggregate = TRUE only in 2011,
  # when M91-93/L91-93 don't exist yet; from 2012 on M89/L89 are
  # is_aggregate = FALSE leaves coexisting with M91-93/L91-93.)
  #
  # Pairs are the M/L-prefixed components (this package's ig_long only
  # covers M/L; other prefixes in the same rollup, e.g. N/O/P/Q/R, fall
  # outside its domain and are irrelevant here) enumerated in
  # cog_pipeline's data/wide_to_long_xwalk.csv `full_desc` column (read
  # once at authoring time, not at test time -- this test stays offline):
  #   M47 "To local governments, total (includes N47, O47, P47, R47, and M94)"
  #   M89 "To local governments, total (incl N89, O89, P89, R89, M91, M92, and M93)"
  #   L47 "To state government (includes L94)"
  #   L89 "To state government (includes L91, L92, and L93)"
  con <- .ensure_session()
  pairs <- list(
    list(aggregate = "M47", components = "M94"),
    list(aggregate = "M89", components = c("M91", "M92", "M93")),
    list(aggregate = "L47", components = "L94"),
    list(aggregate = "L89", components = c("L91", "L92", "L93"))
  )
  agg_years_by_code <- DBI::dbGetQuery(con,
    "SELECT DISTINCT year, item_code FROM ig_long WHERE is_aggregate")
  codes_by_year <- DBI::dbGetQuery(con, "SELECT DISTINCT year, item_code FROM ig_long")

  for (p in pairs) {
    agg_years <- agg_years_by_code$year[agg_years_by_code$item_code == p$aggregate]
    for (yr in agg_years) {
      codes_yr <- codes_by_year$item_code[codes_by_year$year == yr]
      has_component <- any(p$components %in% codes_yr)
      expect_false(
        has_component,
        label = sprintf(
          "year %s has aggregate-flagged %s co-occurring with a modern component (%s)",
          yr, p$aggregate, paste(p$components, collapse = ",")
        )
      )
    }
  }
})

test_that(".verb_spendrev rejects expenditure_concept = 'total' for a non-spending view_base", {
  # cog_revenue() never exposes expenditure_concept and always resolves it
  # to the "direct" default, so there is no revenue codepath that reaches
  # this today -- but .verb_spendrev() is shared, and nothing else stops a
  # future caller from passing expenditure_concept = "total" alongside
  # view_base = "revenue_annotated", which would UNION expenditure M/L rows
  # into a revenue result. Exercise the internal helper directly.
  expect_error(
    uscogdata:::.verb_spendrev(
      verb = "cog_revenue_test", view_base = "revenue_annotated",
      subtype_col = "revenue_subtype",
      flow_prefixes = c("T", "A", "U", "B", "C", "D"),
      call = quote(cog_revenue_test()),
      govid = "010000226085", years = 2019L, category = NULL,
      per_capita = FALSE, adjust_to_year = NULL, basis = "raw",
      recipe = NULL, expenditure_concept = "total"
    ),
    class = "uscogdata_expenditure_concept_unsupported"
  )
})

test_that("cog_geographic_rollup refuses expenditure_concept = 'total'", {
  expect_error(
    cog_geographic_rollup(
      govids = list(state = "010000226085"),
      category = "Police", years = 2019,
      expenditure_concept = "total"
    ),
    class = "uscogdata_concept_not_aggregatable"
  )
})

test_that("cog_peer_compare refuses expenditure_concept = 'total'", {
  expect_error(
    cog_peer_compare(
      target_govid = "010000226085", peers = "010000226085",
      category = "Police", years = 2019,
      expenditure_concept = "total"
    ),
    class = "uscogdata_concept_not_aggregatable"
  )
})

test_that("the refusal message names the fix and the reason", {
  err <- tryCatch(
    cog_geographic_rollup(govids = list(state = "010000226085"),
                          category = "Police", years = 2019,
                          expenditure_concept = "total"),
    condition = function(e) e
  )
  msg <- paste(conditionMessage(err), collapse = " ")
  expect_match(msg, "direct")
  expect_match(msg, "double-count|double count")
  expect_match(msg, "cog_geographic_rollup")

  # Test that cog_peer_compare's message names its own function
  err2 <- tryCatch(
    cog_peer_compare(target_govid = "010000226085", peers = "010000226085",
                     category = "Police", years = 2019,
                     expenditure_concept = "total"),
    condition = function(e) e
  )
  msg2 <- paste(conditionMessage(err2), collapse = " ")
  expect_match(msg2, "direct")
  expect_match(msg2, "double-count|double count")
  expect_match(msg2, "cog_peer_compare")
})

test_that("both cross-government verbs still accept the direct default", {
  expect_no_error(
    cog_geographic_rollup(govids = list(state = "010000226085"),
                          category = "Police", years = 2019)
  )
  expect_no_error(
    cog_peer_compare(target_govid = "010000226085", peers = "010000226085",
                     category = "Police", years = 2019)
  )
})

test_that("provenance always records the expenditure concept", {
  d <- cog_spending("010000226085", years = 2019, category = "Police")
  t <- cog_spending("010000226085", years = 2019, category = "Police",
                    expenditure_concept = "total")
  expect_equal(attr(d, "provenance")$expenditure_concept, "direct")
  expect_equal(attr(t, "provenance")$expenditure_concept, "total")
  # The note explains the non-obvious part: how legacy IG was assembled.
  expect_true(nzchar(attr(t, "provenance")$expenditure_concept_note))
  expect_true(is.na(attr(d, "provenance")$expenditure_concept_note) ||
              !nzchar(attr(d, "provenance")$expenditure_concept_note))
})

test_that("the provenance schema documents expenditure_concept", {
  sch <- jsonlite::fromJSON(
    system.file("schemas", "provenance-v1.json", package = "uscogdata"),
    simplifyVector = FALSE
  )
  expect_true("expenditure_concept" %in% names(sch$properties))
})

test_that("a firing suggestion names the intergovernmental counterpart recipe", {
  # Corrections has no legacy leaf rows, so the coverage-gap suggestion fires;
  # corrections_ig_local_combined is its IG counterpart.
  r <- suppressMessages(
    cog_spending("010000226085", years = c(2005, 2011), category = "Corrections")
  )
  sugg <- attr(r, "provenance")$suggestions
  expect_gt(length(sugg), 0L)
  ids <- vapply(sugg, function(s) s$recipe_id %||% "", character(1))
  expect_true("corrections_combined" %in% ids)
  ig <- unlist(lapply(sugg, function(s) s$ig_recipe_id))
  expect_true("corrections_ig_local_combined" %in% ig)
})

test_that("no suggestion fires for a healthy query", {
  r <- cog_spending("010000226085", years = 2019, category = "Police")
  expect_length(attr(r, "provenance")$suggestions, 0L)
})

test_that("a mis-scoped cog_spending() call never attaches an M/L counterpart to a revenue-flavored recipe", {
  # "IG Federal" is a revenue-only category (summary_categories maps it to
  # B-prefixed component codes only; its recipes are ig_federal_b47_wide /
  # ig_federal_b89_wide). A cog_spending() call scoped to it returns zero
  # spending rows for every requested year -- there is no spending
  # component in this category at all -- so the coverage-gap machinery
  # fires for real (not hypothetically) even though this isn't the kind of
  # format-boundary gap the recipe catalog is meant to signpost. This is
  # exactly the live-corpus risk flagged in review: ig_federal_b47_wide's
  # own component codes (B47/B94, suffixes {"47","94"}) are an EXACT
  # suffix-set match for the expenditure recipe ige_local_m47_wide
  # (M47/M94, same suffixes) -- a coincidence of reused digits, not a real
  # Direct/Total pairing. The flow-family gate in
  # .attach_ig_counterparts() must keep ig_recipe_id NULL here.
  r <- suppressMessages(
    cog_spending("010000226085", years = c(2005, 2011), category = "IG Federal")
  )
  sugg <- attr(r, "provenance")$suggestions
  expect_gt(length(sugg), 0L)
  ids <- vapply(sugg, function(s) s$recipe_id %||% "", character(1))
  expect_true("ig_federal_b47_wide" %in% ids)
  ig <- unlist(lapply(sugg, function(s) s$ig_recipe_id))
  expect_length(ig, 0L)
})

test_that("C1: 'total' on a legacy aggregate-only family reports the IG-only figure honestly, not as Direct + IG", {
  # AL state government, Corrections, 2011. Measured pre-fix: 'total'
  # returned $31,358,000 (the IG leg alone, on an aggregate-flagged M04/M05
  # row) with 0 suggestions (the surviving IG row made the gap-detection
  # machinery think the Direct leg was covered) and a note asserting
  # "Total = Direct + intergovernmental" with no caveat. True Direct (via
  # recipe = "corrections_combined") is $521,651,000 -- the IG-only figure
  # is ~6% of it.
  gov <- "010000226085"

  d <- cog_spending(gov, years = 2011, category = "Corrections",
                    expenditure_concept = "direct")
  expect_equal(nrow(d), 0L)

  t <- suppressMessages(cog_spending(
    gov, years = 2011, category = "Corrections", expenditure_concept = "total"
  ))
  expect_equal(nrow(t), 1L)
  expect_equal(t$spend_subtype, "intergovernmental")
  expect_equal(t$amt_nominal, 31358000)

  r <- cog_spending(gov, years = 2011, recipe = "corrections_combined")
  expect_equal(r$amt_nominal, 521651000)

  # C1(a): the recipe hints must fire for "total" exactly as they do for
  # "direct" -- the surviving IG row must not be mistaken for Direct
  # coverage.
  prov <- attr(t, "provenance")
  expect_gt(length(prov$suggestions), 0L)
  ids <- vapply(prov$suggestions, function(s) s$recipe_id %||% "", character(1))
  expect_true("corrections_combined" %in% ids)

  # C1(b): the affected row's notes name a recovering recipe rather than
  # staying silent, and the provenance carries a flag a downstream consumer
  # (e.g. cog-api, which passes provenance through verbatim) can test.
  expect_true(nzchar(t$notes))
  expect_match(t$notes, "unavailable", fixed = TRUE)
  expect_match(t$notes, "corrections_combined", fixed = TRUE)
  expect_true(prov$expenditure_concept_direct_suppressed)

  # The base "Total = Direct + IG" note must NOT stand unqualified when that
  # arithmetic didn't actually happen for this row.
  expect_match(prov$expenditure_concept_note, "NOTE", fixed = TRUE)
  expect_match(prov$expenditure_concept_note,
              "expenditure_concept_direct_suppressed", fixed = TRUE)
})

test_that("C1(b): expenditure_concept_direct_suppressed is FALSE when the Direct leg is present", {
  d <- cog_spending("010000226085", years = 2019, category = "Police",
                    expenditure_concept = "direct")
  t <- cog_spending("010000226085", years = 2019, category = "Police",
                    expenditure_concept = "total")
  expect_false(isTRUE(attr(d, "provenance")$expenditure_concept_direct_suppressed))
  expect_false(isTRUE(attr(t, "provenance")$expenditure_concept_direct_suppressed))
  expect_false(any(nzchar(t$notes[t$spend_subtype == "intergovernmental"]) &
                   grepl("unavailable", t$notes[t$spend_subtype == "intergovernmental"])))
})

# M/I fix: .detect_direct_suppressed() was equating "no Direct sibling row"
# with "Direct was suppressed", but the dominant real cause is a government
# that simply has no direct spending in that category -- correct, ordinary
# data. The fix gates the flag (and its row note) on a harmonization recipe
# ACTUALLY covering that exact (year, canonical_govid, category) triple.

test_that("M/I: true positive, category supplied explicitly (unchanged behavior)", {
  al <- "010000226085"
  t_cat <- suppressMessages(cog_spending(
    al, years = 2011, category = "Corrections", expenditure_concept = "total"
  ))
  expect_true(attr(t_cat, "provenance")$expenditure_concept_direct_suppressed)
  expect_match(t_cat$notes, "corrections_combined", fixed = TRUE)
  expect_match(t_cat$notes, "unavailable", fixed = TRUE)
})

test_that("M/I: true positive, category = NULL now also names the recipe (was the fallback bug)", {
  # Root bug: .build_suggestions() short-circuits to list() when category is
  # NULL, so the note previously always hit its "no covering recipe found"
  # fallback here even though corrections_combined genuinely covers this row.
  al <- "010000226085"
  t_null <- suppressMessages(cog_spending(
    al, years = 2011, category = NULL, expenditure_concept = "total"
  ))
  corr_row <- t_null[t_null$category %in% "Corrections", ]
  expect_equal(nrow(corr_row), 1L)
  expect_true(attr(t_null, "provenance")$expenditure_concept_direct_suppressed)
  expect_match(corr_row$notes, "corrections_combined", fixed = TRUE)
  expect_match(corr_row$notes, "unavailable", fixed = TRUE)
  expect_false(grepl("no covering recipe found", corr_row$notes, fixed = TRUE))
})

test_that("M/I: false positive -- Virginia Education K-12 FY2019 total is NOT flagged", {
  # States fund K-12 through school districts, so the Direct leg (E12/F12/
  # G12) is genuinely, correctly zero -- not suppressed. Must not be flagged
  # and must carry no suppression note.
  va <- "510000227542"
  t_va <- suppressMessages(cog_spending(
    va, years = 2019, category = "Education K-12", expenditure_concept = "total"
  ))
  expect_equal(nrow(t_va), 1L)
  expect_equal(t_va$spend_subtype, "intergovernmental")
  expect_equal(t_va$amt_nominal, 8028179000)
  expect_false(isTRUE(attr(t_va, "provenance")$expenditure_concept_direct_suppressed))
  expect_false(nzchar(t_va$notes) && grepl("unavailable", t_va$notes))
})

test_that("M/I: false positive by construction -- 'Other Education' has no E/F/G code, never flagged", {
  # "Other Education" maps only to M21/L21 in summary_categories -- there is
  # no E/F/G code for it in this corpus at all, so no Direct-recovering
  # recipe can exist and it must never be flagged, in any fixture year.
  con <- uscogdata:::.ensure_session()
  years_all <- DBI::dbGetQuery(con, "SELECT DISTINCT year FROM long ORDER BY year")$year
  states <- DBI::dbGetQuery(con,
    "SELECT DISTINCT canonical_govid FROM long WHERE type = 0")$canonical_govid
  oe <- suppressMessages(cog_spending(
    states, years = years_all, category = "Other Education",
    expenditure_concept = "total"
  ))
  expect_false(isTRUE(attr(oe, "provenance")$expenditure_concept_direct_suppressed))
  expect_false(any(nzchar(oe$notes) & grepl("unavailable", oe$notes)))
})

test_that("M/I: a clean FY2019 category = NULL total query flags far fewer than the pre-fix 32/50 states", {
  con <- uscogdata:::.ensure_session()
  states <- DBI::dbGetQuery(con,
    "SELECT DISTINCT canonical_govid FROM long WHERE type = 0")$canonical_govid
  r <- suppressMessages(cog_spending(
    states, years = 2019, category = NULL, expenditure_concept = "total"
  ))
  ig <- r[r$spend_subtype == "intergovernmental", ]
  flagged <- ig[nzchar(ig$notes) & grepl("unavailable", ig$notes), ]
  expect_lt(length(unique(flagged$canonical_govid)), 32L)
  # Every remaining flagged row must actually name a covering recipe --
  # never the old no-recipe-found fallback.
  expect_true(all(grepl("recipe = '", flagged$notes, fixed = TRUE)))
  expect_false(any(grepl("no covering recipe found", flagged$notes, fixed = TRUE)))
})

test_that("C2: expenditure_concept = 'total' aborts on a corpus with no intergovernmental category rows", {
  with_corpus_missing_ig_categories({
    con <- uscogdata:::.ensure_session()
    n <- DBI::dbGetQuery(con,
      "SELECT COUNT(*) AS n FROM summary_categories WHERE LEFT(item_code, 1) IN ('M', 'L')"
    )$n
    expect_equal(n, 0)

    err <- tryCatch(
      cog_spending("010000226085", years = 2019, category = "Police",
                  expenditure_concept = "total"),
      condition = function(e) e
    )
    expect_s3_class(err, "uscogdata_ig_categories_unsupported")
    msg <- conditionMessage(err)
    expect_match(msg, "PR #59|predates", perl = TRUE)
  })

  # 'direct' is unaffected on the same corpus -- the guard is scoped to
  # expenditure_concept = "total" only.
  with_corpus_missing_ig_categories({
    expect_no_error(
      cog_spending("010000226085", years = 2019, category = "Police",
                  expenditure_concept = "direct")
    )
  })
})

test_that("C2: expenditure_concept = 'total' still works on a corpus that DOES carry M/L category rows", {
  expect_no_error(
    cog_spending("010000226085", years = 2019, category = "Police",
                expenditure_concept = "total")
  )
})

test_that("I2: an intergovernmental (M/L) recipe never appears as its own top-level suggestion", {
  # Task 1's M04/M05 category rows share the "Corrections" summary_categories
  # category with the Direct-flavored E04/E05, so `corrections_ig_local_
  # combined` (entirely M-prefixed) becomes a raw *candidate* in
  # .build_suggestions()'s component_code-driven query. Following a
  # "re-run with recipe = 'corrections_ig_local_combined'" hint on a plain
  # cog_spending() call would silently return intergovernmental dollars
  # under provenance$expenditure_concept = "direct". Task 6's gate
  # (.attach_ig_counterparts()) already protects the *counterpart* lookup;
  # this exercises that the candidate list itself is filtered too.
  r <- suppressMessages(
    cog_spending("010000226085", years = c(2005, 2011), category = "Corrections")
  )
  sugg <- attr(r, "provenance")$suggestions
  ids <- vapply(sugg, function(s) s$recipe_id %||% "", character(1))
  expect_true("corrections_combined" %in% ids)
  expect_false("corrections_ig_local_combined" %in% ids)
})

test_that(".attach_ig_counterparts() never pairs a revenue-side recipe with its coincidental M/L suffix twin", {
  # Broader version of the case above, run at the matching-helper level
  # (the same level code review's pairwise enumeration was done at) rather
  # than end-to-end: the fixture has no (govid, year) combination where
  # cog_revenue() itself produces a covered gap for any B/C/D recipe, so an
  # end-to-end repro for THIS specific set of recipes isn't reachable
  # today. Each of these six recipes shares an exact suffix set with an
  # M/L expenditure recipe purely by reused-digit coincidence:
  #   ig_federal_b47_wide {"47","94"} == ige_local_m47_wide / ige_state_l47_wide
  #   ig_federal_b89_wide {"89","91","92","93"} == ige_local_m89_wide / ige_state_l89_wide
  #   ig_state_c47_wide   {"47","94"} == ige_local_m47_wide / ige_state_l47_wide
  #   ig_state_c89_wide   {"89","91","92","93"} == ige_local_m89_wide / ige_state_l89_wide
  #   ig_local_d47_wide   {"47","94"} == ige_local_m47_wide / ige_state_l47_wide
  #   ig_local_d89_wide   {"89","91","92","93"} == ige_local_m89_wide / ige_state_l89_wide
  # None of them may receive an ig_recipe_id under cog_revenue()'s own
  # flow_prefixes, since M/L only ever pairs with the direct-expenditure
  # (E/F/G) family.
  con <- uscogdata:::.ensure_session()
  fake_suggestion <- function(rid) {
    list(recipe_id = rid, label = "x", available_years = c(1967L, 2023L),
         hint = "h")
  }
  fake_suggestions <- lapply(
    c("ig_federal_b47_wide", "ig_federal_b89_wide",
      "ig_state_c47_wide", "ig_state_c89_wide",
      "ig_local_d47_wide", "ig_local_d89_wide"),
    fake_suggestion
  )
  out <- uscogdata:::.attach_ig_counterparts(
    con, fake_suggestions, c("T", "A", "U", "B", "C", "D")
  )
  ig <- unlist(lapply(out, function(s) s$ig_recipe_id))
  expect_length(ig, 0L)
})
