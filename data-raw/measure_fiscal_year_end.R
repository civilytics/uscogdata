# data-raw/measure_fiscal_year_end.R
#
# Measures how usable `long.fiscal_year_end` is before anything is built on it
# (uscogdata#77, step 1). Reads the long partitions of a corpus directly and
# reports, by survey year and government type (0-3):
#
#   * government-years with no fiscal_year_end on any row (missing),
#   * values of 0, and values that are not a valid MMDD date (implausible),
#   * government-years whose rows disagree on the value,
#   * the most common values,
#   * how often a government's value changes between consecutive years,
#   * every state government's value, and the District of Columbia's.
#
# A "government-year" is one (canonical_govid, year). fiscal_year_end is a
# header field, so every row of a government-year should carry the same value.
#
# Usage, from the package root:
#   Rscript data-raw/measure_fiscal_year_end.R
#   Rscript data-raw/measure_fiscal_year_end.R /path/to/corpus
#
# The default is the bundled fixture, which holds only FY2011, FY2012, FY2019
# and FY2020. Do not generalize its results to other years.

measure_fiscal_year_end <- function(
    corpus = file.path("inst", "extdata", "fixture_corpus")) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  run <- function(sql) DBI::dbExecute(con, sql)
  q <- function(sql) DBI::dbGetQuery(con, sql)

  run(sprintf(
    "CREATE VIEW l AS SELECT * FROM read_parquet('%s/data/long/*/*.parquet',
       hive_partitioning = true)",
    normalizePath(corpus, mustWork = TRUE)
  ))
  run("CREATE MACRO valid_mmdd(x) AS x IS NOT NULL
         AND x // 100 BETWEEN 1 AND 12
         AND x % 100 BETWEEN 1 AND CASE x // 100
               WHEN 2 THEN 29 WHEN 4 THEN 30 WHEN 6 THEN 30
               WHEN 9 THEN 30 WHEN 11 THEN 30 ELSE 31 END")
  run("CREATE TABLE gy AS
       SELECT year, type, canonical_govid,
              any_value(gov_name) AS gov_name,
              any_value(fips_state) AS fips_state,
              COUNT(DISTINCT fiscal_year_end) AS n_values,
              COUNT(*) FILTER (WHERE fiscal_year_end IS NULL) AS n_null_rows,
              COUNT(*) AS n_rows,
              any_value(fiscal_year_end)
                FILTER (WHERE fiscal_year_end IS NOT NULL) AS fye
       FROM l GROUP BY 1, 2, 3")

  list(
    partitions = q("SELECT year, COUNT(*) AS rows FROM l GROUP BY 1 ORDER BY 1"),
    by_year_type = q(
      "SELECT year, type, COUNT(*) AS gov_years,
              SUM((fye IS NULL)::INT) AS missing,
              SUM((fye = 0)::INT) AS zero,
              SUM((fye IS NOT NULL AND fye <> 0 AND NOT valid_mmdd(fye))::INT)
                AS implausible,
              SUM((n_values > 1)::INT) AS conflicting_within_year,
              SUM((n_null_rows > 0 AND n_null_rows < n_rows)::INT)
                AS partly_missing
       FROM gy GROUP BY 1, 2 ORDER BY 1, 2"),
    row_null_share = q(
      "SELECT year, COUNT(*) AS rows,
              AVG((fiscal_year_end IS NULL)::INT) AS null_share
       FROM l GROUP BY 1 ORDER BY 1"),
    top_values = q(
      "WITH c AS (SELECT year, fye, COUNT(*) AS n FROM gy GROUP BY 1, 2),
            r AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY year ORDER BY n DESC) AS rk,
                         n / SUM(n) OVER (PARTITION BY year) AS share FROM c)
       SELECT year, fye, n, share FROM r WHERE rk <= 6 ORDER BY year, rk"),
    changes = q(
      "SELECT a.year AS from_year, b.year AS to_year, a.type,
              COUNT(*) AS in_both_years, SUM((a.fye <> b.fye)::INT) AS changed
       FROM gy a JOIN gy b
         ON a.canonical_govid = b.canonical_govid AND b.year = a.year + 1
       WHERE a.fye IS NOT NULL AND b.fye IS NOT NULL
       GROUP BY 1, 2, 3 ORDER BY 1, 3"),
    states = q(
      "SELECT fips_state, any_value(gov_name) AS gov_name, year, fye
       FROM gy WHERE type = 0 GROUP BY fips_state, year, fye
       ORDER BY fips_state, year"),
    district_of_columbia = q(
      "SELECT year, type, canonical_govid, gov_name, fye
       FROM gy WHERE fips_state = 11 ORDER BY year")
  )
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  res <- if (length(args) > 0L) {
    measure_fiscal_year_end(args[[1]])
  } else {
    measure_fiscal_year_end()
  }
  for (nm in names(res)) {
    cat("\n==", nm, "\n")
    print(res[[nm]], row.names = FALSE)
  }
}
