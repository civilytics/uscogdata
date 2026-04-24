# R/session.R

#' Internal: open session, register views, cache manifest.
#' Not exported. Called lazily by verbs via .ensure_session().
#' @noRd
cog_open <- function(url = .resolve_url(),
                     cache_dir = .resolve_cache_dir()) {
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")

  manifest <- .fetch_or_cache_manifest(url, cache_dir)
  .validate_schema(manifest, expected_version = 3L)
  .validate_scope(manifest)

  .register_views(con, url, manifest)

  .uscogdata_env$con       <- con
  .uscogdata_env$manifest  <- manifest
  .uscogdata_env$url       <- url
  .uscogdata_env$cache_dir <- cache_dir

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

#' @noRd
#' Check which of the supplied govids exist in canonical_fips_xwalk.
#' Emits a cli message listing any missing ones alongside a pointer to the
#' v0.1 scope explanation; returns both sets so callers can attach them to
#' provenance.
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
      i = "v0.1 covers gov_types 0-3 (state/county/city/township). Types 4/5 excluded; see vignette('coverage-scope')."
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
}
