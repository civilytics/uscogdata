# R/manifest.R

# Sentinel substring baked into the placeholder default URL. If we see this
# in the resolved URL, the user hasn't configured USCOGDATA_URL yet.
.PLACEHOLDER_TOKEN <- "REPLACE_WITH_SHARE_TOKEN"

#' Abort with actionable guidance when the resolved corpus URL is still the
#' placeholder shipped with the package (or any URL containing the sentinel).
#' Called from `cog_open()` before any I/O so users see a clear message
#' instead of a downstream JSON parse error.
#' @noRd
.check_url_configured <- function(url) {
  if (!is.character(url) || length(url) != 1L || !nzchar(url)) {
    cli::cli_abort(c(
      "USCOGDATA_URL is not configured.",
      i = "Set the corpus location via one of:",
      "*" = "{.code Sys.setenv(USCOGDATA_URL = \"<url-or-local-path>/\")}",
      "*" = "{.code options(uscogdata.url = \"<url-or-local-path>/\")}",
      i = "For an offline smoke test, use the bundled fixture: {.code system.file(\"extdata/fixture_corpus\", package = \"uscogdata\")}."
    ), class = "uscogdata_url_not_configured")
  }
  if (grepl(.PLACEHOLDER_TOKEN, url, fixed = TRUE)) {
    sentinel <- .PLACEHOLDER_TOKEN
    cli::cli_abort(c(
      "USCOGDATA_URL is not configured (placeholder URL detected).",
      x = "Current value contains the sentinel {.val {sentinel}}: {.url {url}}",
      i = "Set the corpus location via one of:",
      "*" = "{.code Sys.setenv(USCOGDATA_URL = \"<url-or-local-path>/\")}",
      "*" = "{.code options(uscogdata.url = \"<url-or-local-path>/\")}",
      i = "For an offline smoke test, use the bundled fixture: {.code system.file(\"extdata/fixture_corpus\", package = \"uscogdata\")}.",
      i = "For the live Civilytics corpus, request the Nextcloud share URL from the package maintainer."
    ), class = "uscogdata_url_not_configured")
  }
  invisible(url)
}

#' Try to parse a JSON file. Returns parsed object on success, NULL on
#' any parse failure (so callers can decide whether to refetch).
#' @noRd
.try_parse_manifest_file <- function(path) {
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

#' Abort with a clear, classified error when a manifest payload (string or
#' file) cannot be parsed as JSON. Surfaces the URL, content-type if known,
#' and the underlying parse error.
#' @noRd
.abort_invalid_manifest <- function(source, content_type = NA_character_, parse_error = NULL) {
  ct <- if (is.na(content_type) || !nzchar(content_type)) "<unknown>" else content_type
  pmsg <- if (is.null(parse_error)) "" else conditionMessage(parse_error)
  cli::cli_abort(c(
    "Corpus manifest is not valid JSON.",
    x = "Source: {source}",
    i = "Content-Type: {ct}",
    i = "Likely causes: USCOGDATA_URL points at a login page, a 404 HTML page, or the wrong share; or the corpus has not been published yet.",
    i = "Set USCOGDATA_URL to a directory (local path or HTTPS) that serves manifest.json directly.",
    if (nzchar(pmsg)) c(">" = "Parse error: {pmsg}") else NULL
  ), class = "uscogdata_invalid_manifest")
}

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
    return(tryCatch(
      jsonlite::fromJSON(local_manifest, simplifyVector = FALSE),
      error = function(e) .abort_invalid_manifest(source = local_manifest, parse_error = e)
    ))
  }

  cache_path <- file.path(cache_dir, "manifest.json")
  ttl <- as.integer(.cfg("manifest_ttl_secs"))

  cache_fresh <- file.exists(cache_path) &&
    difftime(Sys.time(), file.info(cache_path)$mtime, units = "secs") <= ttl

  # Honor a fresh cache only if its contents still parse as JSON. A previous
  # version of this package could write HTML directly into the cache; treat
  # such poisoned caches as if they were missing so the next call recovers.
  if (cache_fresh) {
    parsed <- .try_parse_manifest_file(cache_path)
    if (!is.null(parsed)) return(parsed)
  }

  resp <- httr2::request(paste0(url, "manifest.json")) |>
    httr2::req_error(is_error = function(r) httr2::resp_status(r) >= 400) |>
    httr2::req_perform()
  body <- httr2::resp_body_string(resp)

  # Parse BEFORE persisting. If the server returned HTML / a login page /
  # any non-JSON body with a 2xx status, we must not write it to the cache.
  parsed <- tryCatch(
    jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(e) {
      ct <- tryCatch(httr2::resp_content_type(resp), error = function(e2) NA_character_)
      .abort_invalid_manifest(
        source = paste0(url, "manifest.json"),
        content_type = ct,
        parse_error = e
      )
    }
  )

  # Atomic write: tmp file alongside cache_path (same filesystem -> no EXDEV)
  # then rename. Ensures a partial write or interrupted process never
  # replaces a previously-good cache.
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  tmp <- paste0(cache_path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  writeLines(body, tmp)
  file.rename(tmp, cache_path)
  parsed
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
