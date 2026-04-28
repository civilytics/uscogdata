# R/basket.R
#
# Internals supporting the basket-mode sidecar (constructed in
# .resolve_basket() — see R/search.R) plus the user-facing accessors
# cog_basket_resolution() and cog_basket_unresolved() (added in a
# later step).

# Build the sidecar tibble. One row per input; carries query_*, status,
# match_method, canonical_govid, gov_name, n_candidates, and a list-col
# `candidates` of full-schema match-candidate tibbles.
#' @noRd
.build_sidecar <- function(args, resolved) {
  type_label <- unname(vapply(args$type, function(t) {
    if (is.na(t)) NA_character_ else .type_to_label(t)
  }, character(1)))

  status <- vapply(resolved, `[[`, character(1), "status")
  method <- vapply(resolved, `[[`, character(1), "match_method")
  ncand  <- vapply(resolved, `[[`, integer(1),  "n_candidates")
  govid  <- vapply(resolved, function(r) {
    if (nrow(r$row) == 0L) NA_character_ else r$row$canonical_govid[1L]
  }, character(1))
  gname  <- vapply(resolved, function(r) {
    if (nrow(r$row) == 0L) NA_character_ else r$row$gov_name[1L]
  }, character(1))
  cands  <- lapply(resolved, `[[`, "candidates")

  tibble::tibble(
    query_name      = args$name,
    query_state     = args$state,
    query_type      = type_label,
    status          = status,
    match_method    = method,
    canonical_govid = govid,
    gov_name        = gname,
    n_candidates    = ncand,
    candidates      = cands
  )
}

# Convert a type input (integer-like or label) into the canonical label
# string used in the sidecar query_type column.
#' @noRd
.type_to_label <- function(type) {
  int_type <- .coerce_type(type)
  unname(c("0" = "state", "1" = "county", "2" = "city", "3" = "township")[[as.character(int_type)]])
}

# Single post-resolution summary message. Silent on clean baskets;
# emits one cli_inform with two-line body otherwise.
#' @noRd
.basket_summary_message <- function(sidecar) {
  status     <- sidecar$status
  n_input    <- length(status)
  n_basket   <- sum(status %in% c("resolved", "largest_pop"))
  n_amb      <- sum(status == "ambiguous")
  n_nm       <- sum(status == "no_match")
  n_lp       <- sum(status == "largest_pop")

  if (n_amb == 0L && n_nm == 0L && n_lp == 0L) return(invisible(NULL))

  parts <- c(
    if (n_amb > 0L) sprintf("%d ambiguous", n_amb),
    if (n_nm  > 0L) sprintf("%d with no match", n_nm),
    if (n_lp  > 0L) sprintf("%d used largest-population fallback", n_lp)
  )

  cli::cli_inform(c(
    i = sprintf("Basket resolved %d of %d entries.", n_basket, n_input),
    i = paste(parts, collapse = ", "),
    i = "Inspect with `cog_basket_resolution(result)` or filter to problem rows with `cog_basket_unresolved(result)`."
  ))
  invisible(NULL)
}

#' Inspect basket-mode resolution sidecar
#'
#' Returns the resolution tibble attached to a basket-mode result of
#' [cog_gov_search()]. One row per input entry; `status` is one of
#' `"resolved"`, `"largest_pop"`, `"ambiguous"`, `"no_match"`. By default
#' the `candidates` list-column is dropped for readable printing; pass
#' `expand_candidates = TRUE` to keep it.
#'
#' @param x A tibble returned by basket-mode [cog_gov_search()].
#' @param expand_candidates Logical. If `TRUE`, keeps the `candidates`
#'   list-column (full-schema match candidates per input row). Default
#'   `FALSE`.
#' @return A tibble with the resolution audit trail.
#' @export
cog_basket_resolution <- function(x, expand_candidates = FALSE) {
  res <- attr(x, "resolution")
  if (is.null(res)) {
    cli::cli_abort(c(
      "`x` has no resolution attribute.",
      i = "Pass the result of basket-mode `cog_gov_search()` (length(name) > 1).",
      i = "Single-name (utility) results do not carry a sidecar."
    ))
  }
  if (!isTRUE(expand_candidates)) {
    res$candidates <- NULL
  }
  res
}

#' Filter a basket resolution to unresolved rows
#'
#' Convenience wrapper that returns just the rows where `status` is
#' `"ambiguous"` or `"no_match"` — the ones the user likely wants to
#' refine before piping into a query verb. The `candidates` list-column
#' is preserved so the user can drill into ambiguous match sets.
#'
#' @param x A tibble returned by basket-mode [cog_gov_search()].
#' @return A tibble (subset of [cog_basket_resolution()]).
#' @export
cog_basket_unresolved <- function(x) {
  res <- cog_basket_resolution(x, expand_candidates = TRUE)
  res[res$status %in% c("ambiguous", "no_match"), , drop = FALSE]
}
