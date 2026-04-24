# R/peers.R

#' Find peer governments by similarity criteria
#'
#' Selects peer governments from `canonical_fips_xwalk` by combinations of
#' government type, state, and population range. Peers are ordered by
#' `|log(pop_ratio)|` ascending (closest to the target's population first).
#'
#' @param target_govid Character scalar — `canonical_govid` of the target.
#' @param same_type If `TRUE` (default) restrict peers to the target's
#'   `govs_type`.
#' @param same_state If `TRUE` restrict peers to the target's `fips_state`.
#'   Default `FALSE`.
#' @param pop_range Length-2 numeric vector giving lower/upper bounds.
#' @param is_ratio If `TRUE` (default) `pop_range` is multiplied by the
#'   target's `population_acs` to produce absolute bounds. If `FALSE`,
#'   `pop_range` is interpreted as absolute population counts.
#' @param pop_year Reserved for future use (selecting ACS vintage). Currently
#'   the corpus has a single snapshot so this argument has no effect.
#' @param max_peers Integer cap on the number of peers returned.
#' @return Tibble with columns `canonical_govid`, `gov_name`, `fips_state`,
#'   `population_acs`, `pop_ratio`, `rank`.
#' @export
cog_find_peers <- function(target_govid,
                           same_type = TRUE,
                           same_state = FALSE,
                           pop_range = c(0.7, 1.3),
                           is_ratio = TRUE,
                           pop_year = NULL,
                           max_peers = 10L) {
  if (!is.character(target_govid) || length(target_govid) != 1L) {
    cli::cli_abort("`target_govid` must be a length-1 character string.")
  }
  if (!is.numeric(pop_range) || length(pop_range) != 2L ||
      pop_range[1] >= pop_range[2]) {
    cli::cli_abort("`pop_range` must be a length-2 numeric with lo < hi.")
  }

  con <- .ensure_session()

  target_sql <- sprintf(
    "SELECT canonical_govid, gov_name, govs_type, fips_state, population_acs
     FROM canonical_fips_xwalk
     WHERE canonical_govid = %s",
    .sql_lit_chr(target_govid)
  )
  target <- DBI::dbGetQuery(con, target_sql)
  if (nrow(target) == 0L) {
    cli::cli_abort(c(
      "govid {target_govid} not found in corpus.",
      i = "v0.1 covers types 0-3 only (state/county/city/township); see vignette('coverage-scope')."
    ))
  }
  if (is.na(target$population_acs) || target$population_acs <= 0) {
    cli::cli_abort("Target {target_govid} has missing or non-positive population; cannot build pop_ratio band.")
  }

  if (isTRUE(is_ratio)) {
    lo <- target$population_acs * pop_range[1]
    hi <- target$population_acs * pop_range[2]
  } else {
    lo <- pop_range[1]; hi <- pop_range[2]
  }

  preds <- c(
    sprintf("canonical_govid != %s", .sql_lit_chr(target_govid)),
    sprintf("population_acs BETWEEN %.6f AND %.6f", lo, hi)
  )
  if (isTRUE(same_type))  preds <- c(preds, sprintf("govs_type = %d", target$govs_type))
  if (isTRUE(same_state)) preds <- c(preds, sprintf("fips_state = %s", .sql_lit_chr(target$fips_state)))

  peers_sql <- sprintf(
    "SELECT canonical_govid, gov_name, fips_state, population_acs,
            population_acs / %.6f AS pop_ratio
     FROM canonical_fips_xwalk
     WHERE %s
     ORDER BY ABS(LN(CAST(population_acs AS DOUBLE) / %.6f))
     LIMIT %d",
    target$population_acs,
    paste(preds, collapse = " AND "),
    target$population_acs,
    as.integer(max_peers)
  )
  peers <- tibble::as_tibble(DBI::dbGetQuery(con, peers_sql))
  if (nrow(peers) > 0L) peers$rank <- seq_len(nrow(peers))
  else peers$rank <- integer(0)
  peers
}

#' Compare a target government against a peer set
#'
#' Pulls spending for the target plus a peer set (either a
#' [cog_find_peers()] result or a character vector of `canonical_govid`) and
#' appends peer-distribution summary rows (`summary_p25`, `summary_p50`,
#' `summary_p75`) so the result can be faceted by `role` in a single ggplot
#' call.
#'
#' @param target_govid Character scalar.
#' @param peers A tibble from [cog_find_peers()] or a character vector of
#'   `canonical_govid`s.
#' @param category Character scalar or vector.
#' @param years Integer vector.
#' @param per_capita Default `TRUE` — peer compare usually normalizes by
#'   population.
#' @param adjust_to_year Integer base year for CPI-U conversion or `NULL`.
#' @return Tibble matching [cog_spending()]'s columns, plus a `role`
#'   column taking values `"target"`, `"peer"`, `"summary_p25"`,
#'   `"summary_p50"`, or `"summary_p75"`, and `target_rank` (target's rank
#'   among target+peers at `max(years)`, NA for other rows). Provenance
#'   attribute reports `verb = "cog_peer_compare"` and `peer_count`.
#' @export
cog_peer_compare <- function(target_govid, peers, category, years,
                             per_capita = TRUE, adjust_to_year = NULL) {
  call <- match.call()
  if (!is.character(target_govid) || length(target_govid) != 1L) {
    cli::cli_abort("`target_govid` must be a length-1 character string.")
  }
  peer_govids <- if (is.data.frame(peers)) {
    as.character(peers$canonical_govid)
  } else {
    as.character(peers)
  }
  peer_govids <- peer_govids[!is.na(peer_govids) & nzchar(peer_govids)]
  all_govids <- unique(c(target_govid, peer_govids))

  r <- cog_spending(all_govids, years, category, per_capita, adjust_to_year)
  r$role <- ifelse(r$canonical_govid == target_govid, "target", "peer")

  value_col <- .peer_value_col(per_capita, adjust_to_year)

  summary_rows <- .peer_summary_rows(r, value_col)
  out <- dplyr::bind_rows(r, summary_rows)
  rank_val <- .peer_target_rank(r, target_govid, years, value_col)
  out$target_rank <- ifelse(out$role == "target", rank_val, NA_integer_)

  prov <- attr(r, "provenance") %||% list()
  prov$verb       <- "cog_peer_compare"
  prov$call       <- paste(deparse(call), collapse = " ")
  prov$peer_count <- length(peer_govids)
  prov$target     <- list(
    canonical_govid = target_govid,
    gov_name        = unique(r$gov_name[r$role == "target"])
  )
  attr(out, "provenance") <- prov
  out
}

#' @noRd
.peer_value_col <- function(per_capita, adjust_to_year) {
  if (!is.null(adjust_to_year)) {
    if (isTRUE(per_capita)) "amt_per_capita_real" else "amt_real"
  } else {
    if (isTRUE(per_capita)) "amt_per_capita_nominal" else "amt_nominal"
  }
}

#' @noRd
.peer_summary_rows <- function(r, value_col) {
  peer_rows <- r[r$role == "peer", , drop = FALSE]
  if (nrow(peer_rows) == 0L) {
    return(r[integer(0), , drop = FALSE])
  }
  s <- peer_rows |>
    dplyr::group_by(.data$year, .data$spend_subtype, .data$category) |>
    dplyr::reframe(
      q     = c("p25", "p50", "p75"),
      value = stats::quantile(
        .data[[value_col]], c(0.25, 0.50, 0.75), na.rm = TRUE
      )
    )
  s$role <- paste0("summary_", s$q)
  s$gov_name <- dplyr::case_when(
    s$q == "p25" ~ "Peer P25",
    s$q == "p50" ~ "Peer median",
    s$q == "p75" ~ "Peer P75",
    TRUE         ~ NA_character_
  )
  s$canonical_govid <- NA_character_
  out <- s[, c("year", "canonical_govid", "gov_name",
               "spend_subtype", "category", "role")]
  out[[value_col]] <- s$value
  out
}

#' @noRd
.peer_target_rank <- function(r, target_govid, years, value_col) {
  if (nrow(r) == 0L) return(NA_integer_)
  latest <- max(as.integer(years))
  latest_rows <- r[r$year == latest &
                   r$role %in% c("target", "peer"), , drop = FALSE]
  if (nrow(latest_rows) == 0L) return(NA_integer_)
  ranked <- dplyr::arrange(latest_rows, dplyr::desc(.data[[value_col]]))
  tr <- which(ranked$canonical_govid == target_govid)[1]
  if (length(tr) == 0L || is.na(tr)) NA_integer_ else as.integer(tr)
}
