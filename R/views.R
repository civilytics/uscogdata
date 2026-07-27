# R/views.R

# SQL files that cannot be registered unconditionally against a v4 corpus,
# for one of two distinct reasons -- both fail at CREATE VIEW time (DuckDB
# resolves a view's source schema eagerly, even though it defers execution),
# so a v4 corpus can't tolerate either unconditionally:
#
#  (a) Missing FILE. 33-/34-/35- read_parquet() a v5-only parquet table
#      (harmonization_map.parquet, harmonization_recipes.parquet,
#      series_breaks.parquet) that doesn't exist at all on a v4 corpus --
#      "IO Error: No files found".
#
#  (b) Missing COLUMN. 22-/23-/25- reference `long.harmonized_code`, a
#      column that does not exist on a v4 corpus's `long` table (harmonized
#      space was introduced in schema v5) -- "Binder Error: Referenced
#      column harmonized_code not found". 42-/43-/45- are on this list only
#      because they SELECT s.* FROM the (a)/(b) views above, so they'd fail
#      to resolve their own source view if it weren't already skipped.
#
# Registration is therefore gated on manifest$schema_version >= 5 for all of
# them; verb-level *usage* of the resulting views is separately gated by
# .resolve_basis() / .require_schema_v5().
.harmonization_view_files <- c(
  "22-spending_long_harmonized.sql",
  "23-revenue_long_harmonized.sql",
  "25-ig_long_harmonized.sql",
  "33-harmonization_map.sql",
  "34-harmonization_recipes.sql",
  "35-series_breaks_pq.sql",
  "42-spending_annotated_harmonized.sql",
  "43-revenue_annotated_harmonized.sql",
  "45-ig_annotated_harmonized.sql"
)

#' Register DuckDB views from inst/sql/ SQL files
#' @noRd
.register_views <- function(con, url, manifest) {
  sql_dir <- system.file("sql", package = "uscogdata")
  files   <- sort(list.files(sql_dir, pattern = "\\.sql$", full.names = TRUE))
  schema_version <- suppressWarnings(as.integer(manifest$schema_version %||% 0L))
  for (f in files) {
    if (basename(f) %in% .harmonization_view_files && schema_version < 5L) next
    sql <- paste(readLines(f, warn = FALSE), collapse = "\n")
    sql <- gsub("\\{url\\}", url, sql, fixed = FALSE)
    DBI::dbExecute(con, sql)
  }
}
