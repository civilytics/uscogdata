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

# Cash and security holdings (uscogdata#25). 46- selects
# `c.balance_subtype`, a column that arrived with cog_pipeline #76/#77 and
# WITHOUT a schema_version bump -- so neither existing gate applies:
# .harmonization_view_files keys on schema_version, .representation_view_files
# on the presence of a FILE. Here the discriminator is a COLUMN on a table
# that exists either way. CREATE VIEW resolves its source schema eagerly, so
# on an older corpus 46- would fail at registration with "Binder Error:
# Referenced column balance_subtype not found" rather than at query time.
.balance_view_files <- c("26-balance_long.sql", "46-balance_annotated.sql")

#' Does the mounted corpus's `summary_categories` carry `balance_subtype`?
#' Probed against the live connection rather than the manifest, because the
#' manifest describes files, not columns.
#' @noRd
.corpus_has_balance_subtype <- function(con) {
  n <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM information_schema.columns
     WHERE table_name = 'summary_categories'
       AND column_name = 'balance_subtype'"
  )$n
  isTRUE(as.integer(n) > 0L)
}

#' Does the mounted corpus publish `file` (e.g. "code_set.parquet")?
#' Reads the manifest's metadata list rather than stat-ing the URL, so it
#' works identically for a local fixture and a remote share.
#' @noRd
.corpus_has_table <- function(manifest, file) {
  paths <- vapply(manifest$files$metadata %||% list(),
                  function(f) as.character(f$path %||% ""), character(1))
  file %in% basename(paths)
}

#' Build the SQL path expression for the partitioned `long` table.
#'
#' DuckDB cannot expand a glob over generic HTTP: there is no directory
#' listing to expand against, and `allow_asterisks_in_http_paths` only
#' forwards the literal `**/*` as a filename, which 404s. Measured against
#' the published corpus on 2026-08-08, an explicit file list returns the
#' same 46,148,034 rows the (working) `hf://` glob does, and
#' `hive_partitioning = true` still recovers `year` from the paths.
#'
#' The manifest already enumerates every partition, so we build the list
#' from it. This is host-agnostic -- Nextcloud, HuggingFace and a local
#' fixture take the same path -- where an `hf://` URL would tie the reader
#' to one vendor's protocol and still need special-casing, since manifest
#' fetching goes through httr2, which cannot speak `hf://`.
#'
#' Falls back to the glob when the manifest carries no partition list: a
#' hand-built manifest in a test (see test-views.R) or a corpus predating
#' the field. Both are local, where globbing works.
#' @noRd
.long_files_sql <- function(url, manifest) {
  parts <- manifest$files$long_partitions %||% list()
  if (length(parts) == 0L) {
    return(.sql_lit_chr(paste0(url, "data/long/**/*.parquet")))
  }
  paths <- vapply(parts, function(p) as.character(p$path), character(1))
  paste0("[", .sql_lit_chr(paste0(url, paths)), "]")
}

#' Substitute the corpus-location tokens in a view's SQL text.
#'
#' One place knows the token vocabulary. `.register_views()` and the tests
#' that execute a view file directly both route through here. This exists
#' because four test sites had hand-rolled the `{url}` substitution -- one
#' of them commented as doing it "exactly as .register_views() does" -- and
#' every one of them broke the moment a second token was introduced.
#'
#' `{long_files}` must be substituted BEFORE `{url}`: it expands to a string
#' that itself contains the url, so the reverse order leaves the token in
#' place and DuckDB's parser fails on the brace.
#'
#' `manifest` defaults to empty, which routes `.long_files_sql()` to its glob
#' fallback -- correct for the local temp corpora the direct-execution tests
#' build.
#' @noRd
#' `fixed = TRUE` is load-bearing, not a style choice.
#'
#' In regex mode, `gsub()` interprets backslashes in the REPLACEMENT string as
#' escape sequences and silently drops them. A Windows corpus path is full of
#' them, so `C:\Users\RUNNER\AppData\...` was substituted in as
#' `C:UsersRUNNERAppData...` and every DuckDB read failed with "No files found
#' that match the pattern". `fixed = TRUE` treats pattern and replacement as
#' literal text, which is what a filesystem path needs.
#'
#' This is why the package could not read a LOCAL corpus on Windows at all --
#' including the test fixture, hence the entire suite, and any `cog_mirror()`
#' copy. Remote https URLs were unaffected, having no backslashes, which is
#' part of why it stayed hidden: the bug predates the `{long_files}` token and
#' lived in the original `{url}` substitution, unnoticed because nothing ever
#' ran on Windows until the mirror's check matrix existed.
#' @noRd
.render_view_sql <- function(sql, url, manifest = list()) {
  sql <- gsub("{long_files}", .long_files_sql(url, manifest), sql, fixed = TRUE)
  gsub("{url}", url, sql, fixed = TRUE)
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
    if (base %in% .balance_view_files && !.corpus_has_balance_subtype(con)) next
    sql <- paste(readLines(f, warn = FALSE), collapse = "\n")
    sql <- .render_view_sql(sql, url, manifest)
    DBI::dbExecute(con, sql)
  }
}
