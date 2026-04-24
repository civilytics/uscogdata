# R/manifest.R

#' Fetch manifest.json from URL (or read from a local fixture path),
#' cache locally, validate TTL.
#' @noRd
.fetch_or_cache_manifest <- function(url, cache_dir) {
  # Local fixture path: read manifest directly; skip cache/TTL plumbing so
  # tests pick up regenerated manifests immediately.
  if (.is_local_path(url)) {
    local_manifest <- file.path(url, "manifest.json")
    if (!file.exists(local_manifest)) {
      cli::cli_abort("Local fixture has no manifest.json at {local_manifest}")
    }
    return(jsonlite::fromJSON(local_manifest, simplifyVector = FALSE))
  }

  cache_path <- file.path(cache_dir, "manifest.json")
  ttl <- as.integer(.cfg("manifest_ttl_secs"))

  needs_fetch <- !file.exists(cache_path) ||
                 difftime(Sys.time(), file.info(cache_path)$mtime, units = "secs") > ttl

  if (needs_fetch) {
    resp <- httr2::request(paste0(url, "manifest.json")) |>
      httr2::req_error(is_error = function(r) httr2::resp_status(r) >= 400) |>
      httr2::req_perform()
    writeLines(httr2::resp_body_string(resp), cache_path)
  }

  jsonlite::fromJSON(cache_path, simplifyVector = FALSE)
}

#' @noRd
.is_local_path <- function(url) {
  !grepl("^[a-zA-Z][a-zA-Z0-9+.-]*://", url)
}

#' @noRd
.validate_schema <- function(manifest, expected_version) {
  if (manifest$schema_version != expected_version) {
    cli::cli_abort(c(
      "Corpus schema version mismatch.",
      x = "Package expects schema_version = {expected_version}; corpus has {manifest$schema_version}.",
      i = "Update uscogdata (install.packages or pak::pkg_install) or re-publish corpus."
    ))
  }
}

#' @noRd
.validate_scope <- function(manifest) {
  included <- manifest$scope$gov_types_included
  .uscogdata_env$scope_included <- included
  invisible(NULL)
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a
