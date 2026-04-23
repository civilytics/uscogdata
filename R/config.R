# R/config.R

#' Package-private mutable state
#' @noRd
.uscogdata_env <- new.env(parent = emptyenv())

.uscogdata_defaults <- list(
  url               = "https://cloud.civilytics.org/s/REPLACE_WITH_SHARE_TOKEN/download/",
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

.resolve_url <- function() .cfg("url")

.resolve_cache_dir <- function() {
  v <- .cfg("cache_dir")
  if (is.null(v)) tools::R_user_dir("uscogdata", "cache") else v
}
