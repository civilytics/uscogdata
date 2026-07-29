# Helper for the Madison-walkthrough finding tests (uscogdata #11-#16).
#
# Those tests all assert something about what a `cog_*` verb includes or
# excludes. The expected amounts must therefore come from the RAW corpus, never
# from the verb under test: verifying an absence through the filter that creates
# it proves nothing. `wt_raw_*()` opens its own DuckDB connection straight onto
# the corpus's `long` parquet partitions, bypassing uscogdata's SQL views (and
# therefore its `flow_prefixes` filtering) entirely.

wt_corpus_glob <- function() {
  url <- Sys.getenv("USCOGDATA_URL")
  if (!nzchar(url)) testthat::skip("USCOGDATA_URL is not set")
  paste0(sub("/$", "", url), "/data/long/**/*.parquet")
}

wt_raw_query <- function(sql) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sql)
}

# Sum of `amt` (in $1,000s, as the corpus stores it) for one government-year,
# restricted either to an explicit set of item codes or to a set of first-letter
# prefixes. Aggregate rows are excluded, matching every published verb.
wt_raw_amt <- function(govid, year, codes = NULL, prefixes = NULL) {
  stopifnot(xor(is.null(codes), is.null(prefixes)))
  filter_sql <- if (!is.null(codes)) {
    paste0("item_code IN (", paste0("'", codes, "'", collapse = ", "), ")")
  } else {
    paste0("LEFT(item_code, 1) IN (", paste0("'", prefixes, "'", collapse = ", "), ")")
  }
  out <- wt_raw_query(paste0(
    "SELECT COALESCE(SUM(amt), 0) AS amt FROM read_parquet('", wt_corpus_glob(), "') ",
    "WHERE canonical_govid = '", govid, "' AND year = ", year,
    " AND NOT is_aggregate AND ", filter_sql
  ))
  out$amt[[1]]
}

# The item codes a verb reports having summed, flattened out of the
# comma-separated `codes_included` column.
wt_codes_included <- function(df) {
  sort(unique(trimws(unlist(strsplit(stats::na.omit(df$codes_included), ",")))))
}
