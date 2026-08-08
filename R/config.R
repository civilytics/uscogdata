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
  manifest_ttl_secs = 3600L
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
