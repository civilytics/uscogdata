# Madison walkthrough audit -- finding F-025. Tracked as uscogdata#16.
# See docs/walkthroughs/FINDINGS.md in cog_explorer.
#
# cog_gov_search()'s UTILITY mode interpolates `name` into
#   regexp_matches(gov_name, <name>, 'i')
# unescaped (R/search.R:102), while BASKET mode in the same file already routes
# it through .escape_regex() (R/search.R:307) with the comment "so `name` is
# treated as a literal substring". Two failure modes result:
#   correctness -- a real government cannot be found by its own exact name, and
#                  a single "." matches everything (HTTP 200 both ways via the API);
#   robustness  -- malformed regex reaches the engine and errors, which cog-api
#                  surfaces as a 500, reachable by typing a real name one
#                  character at a time.
#
# NOT asserted here: the finding's `q=St. Louis` example. Under correct literal
# matching that search still returns 0 rows, because the stored name is
# "ST LOUIS CITY" with no period -- it demonstrates today's over-matching
# semantics, not a row the fix makes findable.

test_that("cog_gov_search() matches name literally, not as an unescaped regex", {

  # -- correctness (1): a government must be findable by its own exact name ---
  # FREDONIA (BRISCOE) CITY is real; today the parentheses are read as regex
  # grouping, so its own complete name matches nothing.
  fredonia <- cog_gov_search(name = "FREDONIA (BRISCOE) CITY")
  expect_equal(nrow(fredonia), 1L)
  expect_equal(fredonia$canonical_govid, "052117184386")
  expect_equal(cog_gov_search(name = "FREDONIA (BRISCOE)")$canonical_govid,
               "052117184386")

  # -- correctness (2): a metacharacter must not become a wildcard ------------
  # No Wisconsin city or village name contains a literal period -- established
  # against the raw registry below, NOT through the verb under test. A literal
  # search for "." must therefore return nothing; today it returns all 608.
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  xwalk <- paste0(sub("/$", "", Sys.getenv("USCOGDATA_URL")),
                  "/data/canonical_fips_xwalk.parquet")
  with_dot <- DBI::dbGetQuery(con, paste0(
    "SELECT COUNT(*) n FROM read_parquet('", xwalk, "') ",
    "WHERE fips_state = '55' AND govs_type = 2 AND gov_name LIKE '%.%'"))
  expect_equal(as.integer(with_dot$n[[1]]), 0L)

  expect_equal(nrow(cog_gov_search(name = ".", state = "WI", type = "city")), 0L)
  expect_equal(nrow(cog_gov_search(name = "M.dison", state = "WI", type = "city")), 0L)
  expect_equal(nrow(cog_gov_search(name = "Mad(i|o)son", state = "WI", type = "city")), 0L)

  # A metacharacter-free name still resolves exactly as before.
  expect_equal(nrow(cog_gov_search(name = "Madison", state = "WI", type = "city")), 1L)

  # -- robustness: malformed pattern text returns no rows, and does not error --
  # "[" alone, and "Athens-Clarke County (bal" -- an in-progress substring of
  # ATHENS-CLARKE COUNTY (BALANCE), a real government -- both currently raise
  # (DuckDB: "Invalid Input Error: missing ]").
  expect_equal(nrow(cog_gov_search(name = "[")), 0L)
  expect_equal(nrow(cog_gov_search(name = "Athens-Clarke County (bal")), 0L)
})
