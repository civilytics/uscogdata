# R/cache.R
#
# Metadata-table cache for a remote corpus (#64).
#
# Every view over a metadata table (summary_categories, canonical_fips_xwalk,
# code_set and the rest: about 3 MB in all) used to read it over HTTP in
# every session. Keeping those tables in the cache directory, checked against
# the manifest's sha256, cut session open from 1.7 s to 0.4 s against the
# public corpus (2026-11-12, one run per arm). The long partitions stay
# remote; for repeat work on them, cog_mirror() is the tool.
#
# A cached file is used only when its sha256 matches the session's manifest,
# so a republished corpus is picked up as soon as the manifest is. Anything
# that goes wrong falls back to reading every table remotely, as before.

#' Keep the corpus's metadata tables in `cache_dir`, verified by sha256.
#'
#' @param url Corpus root (ends in "/").
#' @param manifest Parsed manifest for `url`.
#' @param cache_dir The session's cache directory.
#' @param fetch `function(src, dest)` that writes the file at URL `src` to
#'   path `dest`. Injectable so the remote path can be tested offline.
#' @return The base the metadata views should read from: a local directory
#'   ending in "/" when every table is cached and verified, otherwise `url`.
#' @noRd
.cache_metadata_tables <- function(url, manifest, cache_dir,
                                   fetch = .fetch_to_file) {
  if (.is_local_path(url)) return(url)
  entries <- manifest$files$metadata
  if (length(entries) == 0L) return(url)
  shas <- vapply(entries, function(e) e$sha256 %||% NA_character_, character(1))
  if (anyNA(shas)) return(url)

  base <- file.path(cache_dir, "corpus")
  for (e in entries) {
    problem <- .cache_one_table(paste0(url, e$path), file.path(base, e$path),
                                e$sha256, fetch)
    if (!is.null(problem)) {
      cli::cli_inform(c(
        "!" = "Reading metadata tables remotely this session: {problem}"
      ))
      return(url)
    }
  }
  paste0(normalizePath(base, winslash = "/"), "/")
}

#' Make `dest` a verified copy of `src`. Returns NULL on success, or a
#' one-line description of what went wrong. A download is written beside
#' `dest` and moved into place only once its sha256 matches, so an
#' unverified file is never left where a later session would read it.
#' @noRd
.cache_one_table <- function(src, dest, sha, fetch) {
  if (file.exists(dest) &&
      digest::digest(dest, algo = "sha256", file = TRUE) == sha) {
    return(NULL)
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(dest, ".tmp.", Sys.getpid())
  on.exit(unlink(tmp), add = TRUE)
  err <- tryCatch({ fetch(src, tmp); NULL },
                  error = function(e) conditionMessage(e))
  if (!is.null(err)) return(sprintf("%s: %s", basename(dest), err))
  if (!file.exists(tmp) ||
      digest::digest(tmp, algo = "sha256", file = TRUE) != sha) {
    return(sprintf("%s did not match its sha256 in the manifest",
                   basename(dest)))
  }
  if (!file.rename(tmp, dest)) {
    return(sprintf("could not write %s", dest))
  }
  NULL
}

#' @noRd
.fetch_to_file <- function(src, dest) {
  httr2::request(src) |>
    httr2::req_error(is_error = function(r) httr2::resp_status(r) >= 400) |>
    httr2::req_perform(path = dest)
  invisible(dest)
}
