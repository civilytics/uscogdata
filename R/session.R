# R/session.R

#' Internal: open session, register views, cache manifest.
#' Not exported. Called lazily by verbs via .ensure_session().
#'
#' `threads` and `memory_limit` default to the resolved configuration and are
#' applied as pragmas on the new connection. When both resolve to NULL -- which
#' is the case unless the operator sets one -- NO pragma is issued at all, so an
#' unconfigured session connects exactly as it did before this argument existed.
#' @noRd
cog_open <- function(url = .resolve_url(),
                     cache_dir = .resolve_cache_dir(),
                     threads = .resolve_duckdb_threads(),
                     memory_limit = .resolve_duckdb_memory_limit()) {
  .check_url_configured(url)
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb())
  # Before anything else touches the connection: httpfs reads the corpus, and
  # a remote read should already be bound by whatever budget the operator set.
  .apply_duckdb_limits(con, threads, memory_limit)
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")

  manifest <- .fetch_or_cache_manifest(url, cache_dir)
  .validate_schema(manifest, supported = c(4L, 5L, 6L, 7L))
  .validate_scope(manifest)

  .register_views(con, url, manifest)

  .uscogdata_env$con       <- con
  .uscogdata_env$manifest  <- manifest
  .uscogdata_env$url       <- url
  .uscogdata_env$cache_dir <- cache_dir

  invisible(con)
}

#' Apply the operator's DuckDB resource budget to a fresh connection.
#'
#' Split out from cog_open() so the "unset changes nothing" property is one
#' readable branch rather than two conditionals buried in the connection path.
#' Both settings are session-scoped in DuckDB, so this must run per connection;
#' cog_close() discards the connection and the next cog_open() re-resolves,
#' which is what makes a changed option take effect on the next session.
#' @noRd
.apply_duckdb_limits <- function(con, threads, memory_limit) {
  if (!is.null(threads)) {
    DBI::dbExecute(con, sprintf("SET threads TO %d", threads))
  }
  if (!is.null(memory_limit)) {
    # Quoted as a string literal: DuckDB's memory_limit takes '4GB', not 4GB.
    DBI::dbExecute(con, sprintf("SET memory_limit TO %s",
                                .sql_lit_chr(memory_limit)))
  }
  invisible(con)
}

#' @noRd
.ensure_session <- function() {
  if (is.null(.uscogdata_env$con) ||
      !DBI::dbIsValid(.uscogdata_env$con)) {
    cog_open()
  }
  .uscogdata_env$con
}

# Coerce an input to a character vector of canonical_govid values.
# Accepts either a character vector (returned as-is after `as.character`)
# or a data.frame / tibble with a `canonical_govid` column (such as the
# output of cog_gov_search() or cog_find_peers()) — in that case the
# column is extracted so results from discovery verbs can pipe directly
# into the query verbs.
#' @noRd
.coerce_govid_input <- function(x, arg = "govid") {
  if (is.data.frame(x)) {
    if (!"canonical_govid" %in% names(x)) {
      cli::cli_abort(c(
        "`{arg}` data frame must have a `canonical_govid` column.",
        i = "Use the result of cog_gov_search() or cog_find_peers() directly, or pass a character vector of canonical_govids."
      ))
    }
    return(as.character(x$canonical_govid))
  }
  if (!is.character(x) && !is.numeric(x)) {
    cli::cli_abort(
      "`{arg}` must be a character vector or a data frame with a `canonical_govid` column."
    )
  }
  as.character(x)
}

# Check which of the supplied govids exist in canonical_fips_xwalk.
# Emits a cli message listing any missing ones alongside a pointer to the
# v0.1 scope explanation; returns both sets so callers can attach them to
# provenance.
#' @noRd
.check_govids_in_scope <- function(govids) {
  govids <- unique(as.character(govids))
  if (length(govids) == 0L) return(list(found = character(0), missing = character(0)))
  con <- .ensure_session()
  sql <- sprintf(
    "SELECT canonical_govid FROM canonical_fips_xwalk WHERE canonical_govid IN (%s)",
    .sql_lit_chr(govids)
  )
  found <- DBI::dbGetQuery(con, sql)$canonical_govid
  missing <- setdiff(govids, found)
  if (length(missing) > 0L) {
    n <- length(missing)
    shown <- paste(utils::head(missing, 5L), collapse = ", ")
    more <- if (n > 5L) sprintf(" (+%d more)", n - 5L) else ""
    cli::cli_inform(c(
      i = sprintf("%d govid%s not found in v0.1 corpus: %s%s",
                  n, if (n == 1L) "" else "s", shown, more),
      i = "Common causes: typo, pre-2017 PID that isn't bridged, or a scope-excluded type (4=special district, 5=school district).",
      i = "Resolve canonical names with cog_gov_search() first."
    ))
  }
  list(found = found, missing = missing)
}

#' @noRd
cog_close <- function() {
  if (!is.null(.uscogdata_env$con) && DBI::dbIsValid(.uscogdata_env$con)) {
    DBI::dbDisconnect(.uscogdata_env$con, shutdown = TRUE)
  }
  .uscogdata_env$con      <- NULL
  .uscogdata_env$manifest <- NULL
  .uscogdata_env$balance_caveats_shown <- NULL
  # Memoised corpus-constant; a different corpus may be mounted next.
  .uscogdata_env$balance_coverage_windows <- NULL
}
