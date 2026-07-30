# data-raw/regenerate_fixture_corpus.R
#
# Regenerate inst/extdata/fixture_corpus/ from a cog_pipeline publish tree.
#
# What this does:
#   1. Copies each requested year's long partition as-is (byte-for-byte)
#      from <publish_cache>/data/long/ into the fixture. Default years are
#      c(2011L, 2012L, 2019L, 2020L): 2011/2012 straddle the wide-aggregate
#      -> modern-leaf format boundary (the harmonization/recipe seam), and
#      2019/2020 are the pre-existing per-capita/CPI regression anchors.
#      Each partition is a full year (all states/govs) as published, so
#      Broward County FL and every other previously-pinned government stay
#      covered without any per-gov slicing logic.
#   2. Copies every metadata parquet the publish tree ships (see
#      .FIXTURE_METADATA_FILES) as-is. These are small cross-vintage
#      registries, not partitioned by year, so the fixture ships the complete
#      tables rather than a year-scoped subset. representation.parquet and
#      code_set.parquet are what make the sparse wide era interpretable --
#      absence means "$0" in a dense_source year and "not reported" in a
#      sparse_source one -- so a fixture without them cannot represent the
#      published corpus.
#   3. Resyncs the four reference docs (data_dictionary.md,
#      reader-specification.md, README.md, series_breaks.md) from the
#      publish tree's docs/.
#   4. Hand-builds manifest.json for just the files the fixture ships,
#      following the shape of the previous fixture manifest but with
#      schema_version bumped to whatever the source manifest reports, and
#      freshly computed sha256 / row_count / size_bytes for every fixture
#      file (never copied from the source manifest, since paths and byte
#      layout can differ subtly between a full corpus and a fixture).
#
# This is never a manual job: run it whenever cog_pipeline publishes a new
# corpus vintage that the fixture should track.
#
# Usage (from the uscogdata package root):
#   Rscript data-raw/regenerate_fixture_corpus.R
#   Rscript data-raw/regenerate_fixture_corpus.R /path/to/publish_cache
#
# Or from R:
#   source("data-raw/regenerate_fixture_corpus.R")
#   regenerate_fixture_corpus(publish_cache_dir = "/path/to/publish_cache")

# Every metadata parquet the publish tree ships, in the order they appear in
# the corpus manifest. Single source of truth for both the copy step and the
# fixture manifest, so the two can never drift apart.
.FIXTURE_METADATA_FILES <- c(
  "canonical_alias.parquet",
  "canonical_fips_xwalk.parquet",
  "census_collection_coverage.parquet",
  "code_set.parquet",
  "harmonization_map.parquet",
  "harmonization_recipes.parquet",
  "lineage_events.parquet",
  "representation.parquet",
  "series_breaks.parquet",
  "summary_categories.parquet"
)

regenerate_fixture_corpus <- function(
    publish_cache_dir = file.path(
      "..", "cog_pipeline", "_targets", "publish_cache"
    ),
    fixture_dir = file.path("inst", "extdata", "fixture_corpus"),
    fixture_years = c(2011L, 2012L, 2019L, 2020L)) {
  stopifnot(
    requireNamespace("digest", quietly = TRUE),
    requireNamespace("jsonlite", quietly = TRUE),
    requireNamespace("duckdb", quietly = TRUE),
    requireNamespace("DBI", quietly = TRUE)
  )

  publish_cache_dir <- normalizePath(publish_cache_dir, mustWork = TRUE)
  if (!dir.exists(fixture_dir)) dir.create(fixture_dir, recursive = TRUE)

  source_manifest <- jsonlite::fromJSON(
    file.path(publish_cache_dir, "manifest.json"),
    simplifyVector = TRUE
  )

  .copy_long_partitions(publish_cache_dir, fixture_dir, fixture_years)
  .copy_metadata_parquets(publish_cache_dir, fixture_dir)
  .copy_docs(publish_cache_dir, fixture_dir)

  manifest <- .build_fixture_manifest(
    fixture_dir, source_manifest, fixture_years
  )
  manifest_path <- file.path(fixture_dir, "manifest.json")
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
    manifest_path
  )

  size_bytes <- sum(file.info(
    list.files(fixture_dir, recursive = TRUE, full.names = TRUE)
  )$size)
  message(sprintf(
    "Fixture corpus regenerated at %s (%.2f MB total).",
    fixture_dir, size_bytes / 1024^2
  ))
  invisible(manifest)
}

# Copy each requested year's partition directory (just the parquet file
# inside it) from the publish tree into the fixture, as-is.
#' @noRd
.copy_long_partitions <- function(publish_cache_dir, fixture_dir, years) {
  for (yr in years) {
    part_rel <- file.path("data", "long", sprintf("year=%d", yr), "part-0.parquet")
    src <- file.path(publish_cache_dir, part_rel)
    dst <- file.path(fixture_dir, part_rel)
    if (!file.exists(src)) {
      stop(sprintf("Source partition missing: %s", src))
    }
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    ok <- file.copy(src, dst, overwrite = TRUE)
    if (!ok) stop(sprintf("Failed to copy %s -> %s", src, dst))
  }
  invisible(NULL)
}

# Copy the full (not year-scoped) metadata tables listed in
# .FIXTURE_METADATA_FILES.
#' @noRd
.copy_metadata_parquets <- function(publish_cache_dir, fixture_dir) {
  for (f in .FIXTURE_METADATA_FILES) {
    src <- file.path(publish_cache_dir, "data", f)
    dst <- file.path(fixture_dir, "data", f)
    if (!file.exists(src)) {
      stop(sprintf("Source metadata file missing: %s", src))
    }
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    ok <- file.copy(src, dst, overwrite = TRUE)
    if (!ok) stop(sprintf("Failed to copy %s -> %s", src, dst))
  }
  invisible(NULL)
}

# Resync the four reference docs shipped alongside the fixture.
#' @noRd
.copy_docs <- function(publish_cache_dir, fixture_dir) {
  docs <- c(
    "data_dictionary.md", "reader-specification.md",
    "README.md", "series_breaks.md"
  )
  dst_dir <- file.path(fixture_dir, "docs")
  dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in docs) {
    src <- file.path(publish_cache_dir, "docs", f)
    if (!file.exists(src)) {
      stop(sprintf("Source doc missing: %s", src))
    }
    ok <- file.copy(src, file.path(dst_dir, f), overwrite = TRUE)
    if (!ok) stop(sprintf("Failed to copy doc %s", f))
  }
  invisible(NULL)
}

# Count rows in a parquet file via an ephemeral DuckDB connection.
#' @noRd
.parquet_row_count <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM read_parquet(%s)",
    .sql_quote(path)
  ))$n
}

#' @noRd
.sql_quote <- function(x) paste0("'", gsub("'", "''", x), "'")

# Hand-build manifest.json following the shape of the previous fixture
# manifest: schema_version / built_at / pipeline_commit / fixture_note /
# data_vintage / scope / schema / files.long_partitions / files.metadata /
# series_breaks_ref / reader_spec_ref. Every sha256 / row_count / size_bytes
# is freshly computed against the files actually written into fixture_dir.
#' @noRd
.build_fixture_manifest <- function(fixture_dir, source_manifest, years) {
  long_partitions <- lapply(years, function(yr) {
    rel <- file.path("data", "long", sprintf("year=%d", yr), "part-0.parquet")
    path <- file.path(fixture_dir, rel)
    list(
      year       = as.integer(yr),
      path       = gsub("\\\\", "/", rel),
      sha256     = digest::digest(path, algo = "sha256", file = TRUE),
      row_count  = as.integer(.parquet_row_count(path)),
      size_bytes = as.integer(file.info(path)$size)
    )
  })

  metadata <- lapply(.FIXTURE_METADATA_FILES, function(f) {
    rel <- file.path("data", f)
    path <- file.path(fixture_dir, rel)
    list(
      path        = gsub("\\\\", "/", rel),
      sha256      = digest::digest(path, algo = "sha256", file = TRUE),
      description = f
    )
  })

  list(
    schema_version = as.integer(source_manifest$schema_version),
    built_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    pipeline_commit = source_manifest$pipeline_commit,
    fixture_note = paste(
      "Four-year (2011, 2012, 2019, 2020) fixture for uscogdata tests. Full",
      "corpus available via USCOGDATA_URL. Regenerated from the sparsified",
      "schema-v6 corpus: the wide era (<= FY2011) no longer stores explicit",
      "zeros, so FY2011 absence means Census published $0 while FY2012+",
      "absence means not reported. representation.parquet and",
      "code_set.parquet carry that rule and ship in full, as do every other",
      "metadata table in the publish tree. 2011/2012 straddle both the",
      "wide-aggregate -> modern-leaf format boundary (exercised by",
      "basis=\"harmonized\" and recipe= queries) and the dense -> sparse",
      "representation boundary (SB194); 2019/2020 retain the prior",
      "per-capita/CPI regression anchors. Regenerated via",
      "data-raw/regenerate_fixture_corpus.R."
    ),
    data_vintage    = source_manifest$data_vintage,
    scope           = source_manifest$scope,
    schema          = source_manifest$schema,
    files = list(
      long_partitions = long_partitions,
      metadata        = metadata
    ),
    series_breaks_ref = source_manifest$series_breaks_ref,
    reader_spec_ref   = source_manifest$reader_spec_ref
  )
}

if (identical(environment(), globalenv()) && sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1L) {
    regenerate_fixture_corpus(publish_cache_dir = args[[1]])
  } else {
    regenerate_fixture_corpus()
  }
}
