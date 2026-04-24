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
}
