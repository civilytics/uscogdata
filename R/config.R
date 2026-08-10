# R/config.R

#' Package-private mutable state
#' @noRd
.uscogdata_env <- new.env(parent = emptyenv())

.uscogdata_defaults <- list(
  # Public HuggingFace mirror of the published corpus: CC-BY-4.0, no
  # credential, CDN-backed. This is the default so `library(uscogdata)`
  # followed by a verb works with zero configuration -- previously the
  # default was a REPLACE_WITH_SHARE_TOKEN sentinel and no document in the
  # package supplied a working URL, so a new user had no path to a session.
  #
  # The trailing slash is required: every consumer concatenates onto this
  # (see .resolve_url(), which enforces it anyway).
  #
  # Override with USCOGDATA_URL or options(uscogdata.url=) to read a
  # Nextcloud share or a local copy made by cog_mirror().
  url               = "https://huggingface.co/datasets/civilytics/us-cog-finance/resolve/main/",
  cache_dir         = NULL,
  manifest_ttl_secs = 3600L,
  # NULL means "emit no pragma", which leaves DuckDB's own defaults intact:
  # every visible core, and 80% of RAM. That is right for one interactive
  # session on a dedicated machine and wrong for a server, where several
  # readers share a box and each would otherwise claim all of it. See
  # .resolve_duckdb_threads() for why this is a supported option rather than
  # something a consumer reaches into the namespace to set.
  duckdb_threads      = NULL,
  duckdb_memory_limit = NULL
)

#' Resolve a config value: env var > option > default
#' @noRd
.cfg <- function(key) {
  env_var <- paste0("USCOGDATA_", toupper(key))
  v <- Sys.getenv(env_var, unset = NA)
  if (!is.na(v) && nzchar(v)) return(v)
  opt <- getOption(paste0("uscogdata.", key), default = NULL)
  if (!is.null(opt)) return(opt)
  .uscogdata_defaults[[key]]
}

#' Resolve the corpus URL, guaranteeing the trailing slash the package assumes.
#'
#' Every consumer builds locations by CONCATENATION -- `paste0(url,
#' "manifest.json")` in manifest.R, `paste0(url, e$path)` in mirror.R, and the
#' parquet glob in views.R -- and mirror.R:104 documents the invariant outright
#' ('url ends in "/"'). Nothing enforced it, so a URL entered without the slash
#' failed silently and misleadingly:
#'
#'   HTTPS -> ".../downloadmanifest.json"; the host answers with an HTML 404
#'            page, which lands in the JSON parser as the lexical error
#'            reported in issue #3 -- pointing the user at "login page / wrong
#'            share" when the real cause was one missing character.
#'   local -> ".../corpusdata/long/**/*.parquet" and a DuckDB "No files found".
#'
#' Normalizing here fixes every consumer at once, rather than each call site
#' re-deriving the same invariant. An empty setting is passed through
#' untouched so manifest.R's "not configured" guard still fires instead of the
#' value degrading into a bare "/" filesystem root.
#' @noRd
.resolve_url <- function() {
  url <- .cfg("url")
  if (is.null(url) || !nzchar(url) || grepl("/$", url)) return(url)
  paste0(url, "/")
}

.resolve_cache_dir <- function() {
  v <- .cfg("cache_dir")
  if (is.null(v)) tools::R_user_dir("uscogdata", "cache") else v
}

#' Resolve the DuckDB thread cap, or NULL to leave DuckDB's default alone.
#'
#' `cog_open()` used to connect with a bare `dbConnect()` and set no `threads`
#' pragma, so DuckDB claimed every core it could see. cog-api works around that
#' by reaching into this namespace at boot --
#' `getFromNamespace(".ensure_session", "uscogdata")()` followed by a manual
#' `SET threads` -- which depends on a private name and on the session already
#' being open. Making it a resolved option removes the reason to do that.
#'
#' `.cfg()` returns an environment variable as CHARACTER, so this coerces
#' rather than trusting the type: `USCOGDATA_DUCKDB_THREADS=4` arrives as "4",
#' and `sprintf("SET threads TO %d", "4")` would abort inside the connection
#' path with an error about the pragma rather than about the setting.
#' @noRd
.resolve_duckdb_threads <- function() {
  v <- .cfg("duckdb_threads")
  if (is.null(v) || (is.character(v) && !nzchar(v))) return(NULL)
  n <- suppressWarnings(as.integer(v))
  if (length(n) != 1L || is.na(n) || n < 1L) {
    cli::cli_abort(c(
      "{.envvar USCOGDATA_DUCKDB_THREADS} must be a single positive integer.",
      x = "Got {.val {v}}.",
      i = "Unset it (or {.code options(uscogdata.duckdb_threads = NULL)}) to use DuckDB's default of every visible core."
    ), class = "uscogdata_invalid_duckdb_threads")
  }
  n
}

#' Resolve the DuckDB memory limit, or NULL to leave DuckDB's default alone.
#'
#' The value is a DuckDB size string (`"4GB"`, `"512MB"`). Only its SHAPE is
#' checked here -- DuckDB owns the unit vocabulary, and re-implementing that
#' parse would be a second definition free to drift from the engine's. An
#' unrecognised unit therefore surfaces as DuckDB's own error at `SET` time,
#' which names the setting correctly; the check here exists to reject the
#' inputs that would otherwise reach the connection as a SQL fragment.
#' @noRd
.resolve_duckdb_memory_limit <- function() {
  v <- .cfg("duckdb_memory_limit")
  if (is.null(v) || (is.character(v) && !nzchar(v))) return(NULL)
  if (length(v) != 1L || !is.character(v) ||
      !grepl("^[0-9]+(\\.[0-9]+)?\\s*[A-Za-z]{0,3}$", v)) {
    cli::cli_abort(c(
      "{.envvar USCOGDATA_DUCKDB_MEMORY_LIMIT} must be a single DuckDB size string.",
      x = "Got {.val {v}}.",
      i = "Examples: {.val 4GB}, {.val 512MB}, {.val 1.5GB}."
    ), class = "uscogdata_invalid_duckdb_memory_limit")
  }
  trimws(v)
}
