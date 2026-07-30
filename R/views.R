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

# The representation contract (cog_pipeline#64): two parquet tables that say
# what an ABSENT cell means in a given year. Gated on manifest PRESENCE, not
# on schema_version, because the sparsification that introduced them did not
# bump the version -- the pre-sparsification corpus this package shipped
# against until 2026-07-30 was already schema v6 and carried neither table.
# Keying off the version number would therefore register a view over a file
# that does not exist and fail at CREATE VIEW time on exactly the corpora this
# check exists to tolerate.
.representation_view_files <- c(
  "36-representation.sql" = "representation.parquet",
  "37-code_set.sql"       = "code_set.parquet"
)

#' Does the mounted corpus publish `file` (e.g. "code_set.parquet")?
#' Reads the manifest's metadata list rather than stat-ing the URL, so it
#' works identically for a local fixture and a remote share.
#' @noRd
.corpus_has_table <- function(manifest, file) {
  paths <- vapply(manifest$files$metadata %||% list(),
                  function(f) as.character(f$path %||% ""), character(1))
  file %in% basename(paths)
}

#' Register DuckDB views from inst/sql/ SQL files
#' @noRd
.register_views <- function(con, url, manifest) {
  sql_dir <- system.file("sql", package = "uscogdata")
  files   <- sort(list.files(sql_dir, pattern = "\\.sql$", full.names = TRUE))
  schema_version <- suppressWarnings(as.integer(manifest$schema_version %||% 0L))
  for (f in files) {
    base <- basename(f)
    if (base %in% .harmonization_view_files && schema_version < 5L) next
    if (base %in% names(.representation_view_files) &&
        !.corpus_has_table(manifest, .representation_view_files[[base]])) next
    sql <- paste(readLines(f, warn = FALSE), collapse = "\n")
    sql <- gsub("\\{url\\}", url, sql, fixed = FALSE)
    DBI::dbExecute(con, sql)
  }
}
