# R/views.R

# SQL files whose view definitions read schema-v5-only parquet tables
# (harmonization_map.parquet, harmonization_recipes.parquet,
# series_breaks.parquet) or select from views built on top of them. DuckDB's
# read_parquet() resolves the file at CREATE VIEW time (even for a view, it
# still needs the source schema) and errors immediately -- "IO Error: No
# files found" -- if the path doesn't exist, so these cannot be registered
# unconditionally against a v4 corpus the way the rest of inst/sql/ is.
# Registration is therefore gated on manifest$schema_version >= 5; verb-level
# *usage* of the resulting views is separately gated by .resolve_basis() /
# .require_schema_v5().
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
