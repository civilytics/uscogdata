# R/mirror.R

#' Mirror the published corpus to a local directory
#'
#' Downloads (or copies, for local-path fixture URLs) every file listed in
#' the session's `manifest.json` into `dest`, preserving the relative path
#' structure. Files already present with a matching SHA-256 hash are
#' skipped unless `overwrite = TRUE`. The resulting directory can be
#' pointed at via `options(uscogdata.url = paste0(dest, "/"))` for offline
#' analysis.
#'
#' @param dest Destination directory. Created if missing.
#' @param include Subset of `c("long", "metadata", "docs")` controlling
#'   which manifest sections to mirror.
#' @param overwrite If `TRUE`, re-copy even when the local SHA matches.
#' @param progress If `TRUE`, show a cli progress bar.
#' @return Invisibly, a tibble of `(path, sha256, size_bytes, status)`
#'   rows where `status` is `"downloaded"` or `"cached"`.
#' @export
cog_mirror <- function(dest,
                       include = c("long", "metadata", "docs"),
                       overwrite = FALSE,
                       progress = interactive()) {
  if (!is.character(dest) || length(dest) != 1L) {
    cli::cli_abort("`dest` must be a length-1 character path.")
  }
  include <- match.arg(include, several.ok = TRUE)
  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)

  .ensure_session()
  url      <- .uscogdata_env$url
  manifest <- .uscogdata_env$manifest
  is_local <- .is_local_path(url)

  .write_manifest_local(manifest, file.path(dest, "manifest.json"))

  entries <- .collect_mirror_entries(manifest, include)
  results <- vector("list", length(entries))
  pb <- if (isTRUE(progress)) {
    cli::cli_progress_bar("Mirroring", total = length(entries))
  } else NULL

  for (i in seq_along(entries)) {
    e <- entries[[i]]
    dest_path <- file.path(dest, e$path)
    .ensure_parent_dir(dest_path)
    status <- .mirror_one_file(
      src_url   = paste0(url, e$path),
      dest_path = dest_path,
      expected_sha = e$sha256,
      is_local  = is_local,
      overwrite = overwrite
    )
    results[[i]] <- tibble::tibble(
      path       = e$path,
      sha256     = e$sha256 %||% NA_character_,
      size_bytes = as.integer(file.info(dest_path)$size),
      status     = status
    )
    if (!is.null(pb)) cli::cli_progress_update()
  }
  if ("docs" %in% include) {
    .mirror_docs(url, dest, is_local, overwrite)
  }
  if (!is.null(pb)) cli::cli_progress_done()
  invisible(dplyr::bind_rows(results))
}

#' @noRd
.write_manifest_local <- function(manifest, path) {
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE),
    path
  )
}

#' @noRd
.collect_mirror_entries <- function(manifest, include) {
  entries <- list()
  if ("long" %in% include && length(manifest$files$long_partitions) > 0L) {
    entries <- c(entries, manifest$files$long_partitions)
  }
  if ("metadata" %in% include && length(manifest$files$metadata) > 0L) {
    entries <- c(entries, manifest$files$metadata)
  }
  entries
}

#' @noRd
.ensure_parent_dir <- function(path) {
  d <- dirname(path)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

#' @noRd
.mirror_one_file <- function(src_url, dest_path, expected_sha,
                             is_local, overwrite) {
  if (!isTRUE(overwrite) && file.exists(dest_path) &&
      !is.null(expected_sha) &&
      digest::digest(dest_path, algo = "sha256", file = TRUE) == expected_sha) {
    return("cached")
  }
  if (isTRUE(is_local)) {
    # src_url was built as paste0(url, e$path); url ends in "/"
    src <- src_url
    if (!file.exists(src)) {
      cli::cli_abort("Source file missing: {src}")
    }
    ok <- file.copy(src, dest_path, overwrite = TRUE)
    if (!isTRUE(ok)) cli::cli_abort("file.copy failed: {src} -> {dest_path}")
  } else {
    resp <- httr2::request(src_url) |>
      httr2::req_error(is_error = function(r) httr2::resp_status(r) >= 400) |>
      httr2::req_perform()
    writeBin(httr2::resp_body_raw(resp), dest_path)
  }
  "downloaded"
}

#' @noRd
.mirror_docs <- function(url, dest, is_local, overwrite) {
  docs <- c("README.md", "data_dictionary.md",
            "series_breaks.md", "reader-specification.md")
  for (doc in docs) {
    src  <- paste0(url, "docs/", doc)
    dst  <- file.path(dest, "docs", doc)
    .ensure_parent_dir(dst)
    if (isTRUE(is_local)) {
      if (file.exists(src)) file.copy(src, dst, overwrite = TRUE)
      # silently skip missing optional docs in local fixtures
      next
    }
    try({
      resp <- httr2::request(src) |>
        httr2::req_error(is_error = function(r) httr2::resp_status(r) >= 400) |>
        httr2::req_perform()
      writeBin(httr2::resp_body_raw(resp), dst)
    }, silent = TRUE)
  }
}
