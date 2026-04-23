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
  .validate_schema(manifest, expected_version = 2L)
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
cog_close <- function() {
  if (!is.null(.uscogdata_env$con) && DBI::dbIsValid(.uscogdata_env$con)) {
    DBI::dbDisconnect(.uscogdata_env$con, shutdown = TRUE)
  }
  .uscogdata_env$con      <- NULL
  .uscogdata_env$manifest <- NULL
}
