# R/peers.R

#' Find peer governments by similarity criteria
#'
#' Selects peer governments by combinations of government type, state, and
#' population range at a chosen `year`. Peers are ordered by `|log(pop_ratio)|`
#' ascending (closest to the target's population first).
#'
#' @param target_govid Character scalar — `canonical_govid` of the target.
#' @param year Integer scalar. Cohort vintage. When `NULL` (default), uses the
#'   most recent year for which the target has an observed population in
#'   `gov_population_yearly`.
#' @param same_type If `TRUE` (default) restrict peers to the target's
#'   `govs_type`.
#' @param same_state If `TRUE` restrict peers to the target's `fips_state`.
#'   Default `FALSE`.
#' @param pop_range Length-2 numeric vector giving lower/upper bounds.
#' @param is_ratio If `TRUE` (default) `pop_range` is multiplied by the
#'   target's population at `year` to produce absolute bounds. If `FALSE`,
#'   `pop_range` is interpreted as absolute population counts.
#' @param max_peers Integer cap on the number of peers returned.
#' @param coverage Survey-cycle handling; see [cog_peer_compare()]. Here it
#'   governs the cohort VINTAGE when `year` is `NULL`: `"census"` snaps to the
#'   most recent census year with an observed population, so a cohort is not
#'   built from a sample year in which most of the candidate universe is
#'   absent. `"consistent"` needs a year range, which cohort selection does not
#'   have, so it selects like `"all"` and is carried on the result as
#'   `attr(x, "coverage")` for [cog_peer_compare()].
#' @return Tibble with columns `canonical_govid`, `gov_name`, `fips_state`,
#'   `population`, `pop_ratio`, `rank`. The cohort year is attached as
#'   `attr(x, "cohort_year")`.
#' @export
cog_find_peers <- function(target_govid,
                           year = NULL,
                           same_type = TRUE,
                           same_state = FALSE,
                           pop_range = c(0.7, 1.3),
                           is_ratio = TRUE,
                           max_peers = 10L,
                           coverage = c("all", "census", "consistent")) {
  coverage <- .validate_coverage(coverage)
  if (!is.character(target_govid) || length(target_govid) != 1L) {
    cli::cli_abort("`target_govid` must be a length-1 character string.")
  }
  if (!is.numeric(pop_range) || length(pop_range) != 2L ||
      pop_range[1] >= pop_range[2]) {
    cli::cli_abort("`pop_range` must be a length-2 numeric with lo < hi.")
  }
  if (!is.null(year) &&
      (!(is.numeric(year) || is.integer(year)) || length(year) != 1L)) {
    cli::cli_abort("`year` must be NULL or a length-1 integer.")
  }

  con <- .ensure_session()

  # Confirm target exists in the xwalk and pull govs_type / fips_state.
  meta_sql <- sprintf(
    "SELECT canonical_govid, gov_name, govs_type, fips_state
     FROM canonical_fips_xwalk
     WHERE canonical_govid = %s",
    .sql_lit_chr(target_govid)
  )
  meta <- DBI::dbGetQuery(con, meta_sql)
  if (nrow(meta) == 0L) {
    cli::cli_abort(c(
      "govid {target_govid} not found in corpus.",
      i = "v0.1 covers types 0-3 only (state/county/city/township); see vignette('coverage-scope')."
    ))
  }

  cohort_year <- .resolve_cohort_year(con, target_govid, year, coverage)

  pop_sql <- sprintf(
    "SELECT population FROM gov_population_yearly
     WHERE canonical_govid = %s AND year = %d",
    .sql_lit_chr(target_govid), as.integer(cohort_year)
  )
  target_pop <- DBI::dbGetQuery(con, pop_sql)$population
  if (length(target_pop) == 0L || is.na(target_pop) || target_pop <= 0) {
    cli::cli_abort(c(
      "Target {target_govid} has no observed population in {cohort_year}.",
      i = "Use a year for which population is observed; see gov_population_yearly."
    ))
  }

  if (isTRUE(is_ratio)) {
    lo <- target_pop * pop_range[1]
    hi <- target_pop * pop_range[2]
  } else {
    lo <- pop_range[1]; hi <- pop_range[2]
  }

  preds <- c(
    sprintf("p.canonical_govid != %s", .sql_lit_chr(target_govid)),
    sprintf("p.year = %d", as.integer(cohort_year)),
    sprintf("p.population BETWEEN %.6f AND %.6f", lo, hi)
  )
  if (isTRUE(same_type))  preds <- c(preds, sprintf("x.govs_type = %d", meta$govs_type))
  if (isTRUE(same_state)) preds <- c(preds, sprintf("x.fips_state = %s", .sql_lit_chr(meta$fips_state)))

  peers_sql <- sprintf(
    "SELECT p.canonical_govid, x.gov_name, x.fips_state, p.population,
            p.population / %.6f AS pop_ratio
     FROM gov_population_yearly p
     JOIN canonical_fips_xwalk x USING (canonical_govid)
     WHERE %s
     ORDER BY ABS(LN(CAST(p.population AS DOUBLE) / %.6f))
     LIMIT %d",
    target_pop,
    paste(preds, collapse = " AND "),
    target_pop,
    as.integer(max_peers)
  )
  peers <- tibble::as_tibble(DBI::dbGetQuery(con, peers_sql))
  peers$rank <- if (nrow(peers) > 0L) seq_len(nrow(peers)) else integer(0)
  attr(peers, "cohort_year") <- as.integer(cohort_year)
  attr(peers, "pop_range")   <- as.numeric(pop_range)
  attr(peers, "is_ratio")    <- isTRUE(is_ratio)
  attr(peers, "coverage")    <- coverage
  attr(peers, "is_census_year") <- .is_census_year(cohort_year)
  peers
}

# `coverage` picks the cohort vintage when the caller did not name one.
# "census" snaps to the most recent CENSUS year with an observed population,
# so a cohort is not silently built from a sample year in which most of the
# candidate universe is absent. "consistent" is a comparison-time concept --
# it needs a year RANGE, which cohort selection does not have -- so it selects
# like "all" here and is carried on the result for cog_peer_compare().
#' @noRd
.resolve_cohort_year <- function(con, target_govid, year,
                                 coverage = "all") {
  if (!is.null(year)) return(as.integer(year))
  if (identical(coverage, "census")) {
    sql <- sprintf(
      "SELECT MAX(year) AS y FROM gov_population_yearly
       WHERE canonical_govid = %s AND year %% 10 IN (2, 7)",
      .sql_lit_chr(target_govid)
    )
    y <- DBI::dbGetQuery(con, sql)$y
    if (length(y) > 0L && !is.na(y)) return(as.integer(y))
    cli::cli_abort(c(
      "{.code coverage = \"census\"} found no census year with an observed population for {target_govid}.",
      i = "Pass an explicit {.arg year}, or use {.code coverage = \"all\"}."
    ), class = "uscogdata_no_census_years")
  }
  sql <- sprintf(
    "SELECT MAX(year) AS y FROM gov_population_yearly
     WHERE canonical_govid = %s",
    .sql_lit_chr(target_govid)
  )
  y <- DBI::dbGetQuery(con, sql)$y
  if (length(y) == 0L || is.na(y)) {
    cli::cli_abort(
      "Target {target_govid} has no observed population in any year."
    )
  }
  as.integer(y)
}

#' Compare a target government against a peer set
#'
#' Pulls spending for the target plus a peer set (either a
#' [cog_find_peers()] result or a character vector of `canonical_govid`) and
#' appends peer-distribution summary rows (`summary_p25`, `summary_p50`,
#' `summary_p75`) so the result can be faceted by `role` in a single ggplot
#' call. Those summary rows are quantiles **within each category**, not
#' quantiles of each peer's total — see the `@return` section before summing
#' them.
#'
#' @param target_govid Character scalar.
#' @param peers A tibble from [cog_find_peers()] or a character vector of
#'   `canonical_govid`s.
#' @param category Character scalar or vector.
#' @param years Integer vector.
#' @param per_capita Default `TRUE` — peer compare usually normalizes by
#'   population.
#' @param adjust_to_year Integer base year for CPI-U conversion or `NULL`.
#' @param expenditure_concept `"primary"` (default), `"direct"`, or
#'   `"total"` -- see [cog_spending()] for the three concepts. `"total"` is
#'   refused here because combining Total across peer sets counts
#'   intergovernmental transfers twice; `"primary"` and `"direct"` combine
#'   safely.
#' @param coverage How to handle the Census of Governments survey cycle,
#'   which is a **complete census only in years ending in 2 and 7** -- every
#'   other year is a sample, and the sample varies enormously (on the bundled
#'   fixture, Wisconsin's 608-city universe reports 597 governments in FY2012
#'   and 112 in FY2019).
#'
#'   * `"all"` (default) -- every unit that reported that year. Unchanged
#'     behaviour, so existing code keeps working.
#'   * `"census"` -- census years only. Aborts if the requested range holds
#'     none, rather than silently returning nothing.
#'   * `"consistent"` -- only units reporting in *every* requested year, giving
#'     a balanced panel.
#'
#'   Regardless of mode, `provenance$coverage` always carries per-year
#'   `n_units_reporting`, `n_units_expected` and `is_census_year`, and
#'   `provenance$coverage_mode` records the mode. `is_census_year` is a
#'   statement about the **survey calendar**, never a claim of completeness:
#'   FY1967 is a census year in which only 97 of Wisconsin's 608 cities
#'   report. `n_units_reporting` is the number that tells the truth.
#'
#'   The comparison target is exempt from `"consistent"` balancing -- it is the
#'   subject of the comparison, not a member of the cohort -- and the
#'   `summary_*` quantiles are computed AFTER the filter, so they describe the
#'   cohort actually returned. `n_units_reporting` counts peers only, against
#'   the cohort size: "3 of your 15 peers reported in FY2019".
#' @return Tibble matching [cog_spending()]'s columns, plus a `role`
#'   column taking values `"target"`, `"peer"`, `"summary_p25"`,
#'   `"summary_p50"`, or `"summary_p75"`, `target_rank` (target's rank
#'   among target+peers at `max(years)`, NA for other rows), and
#'   `cohort_year` (the year used to build the peer cohort, read from
#'   `attr(peers, "cohort_year")`; `NA` when `peers` was a bare character
#'   vector). Provenance reports `verb = "cog_peer_compare"`, `peer_count`,
#'   `cohort_year`, and `cohort_govids`.
#'
#'   **The `summary_*` rows are per-category quantiles: they are not additive.**
#'   Each one is computed **within each `(year, spend_subtype,
#'   category)` cell** across the peer set, so a `summary_p50` row is *the
#'   median peer's value in that one category*, not *the value of the median
#'   peer's total*. The median peer for Police and the median peer for Fire
#'   are usually different governments, so summing `summary_*` rows across
#'   categories does not give any peer's total and misstates the band it
#'   appears to describe — measured at −32.7% to +251.0% across 24 years on
#'   one cohort, with a sign flip at FY2012.
#'
#'   Facet by `role` **and** `category` (the documented use, and what the
#'   rows are built for). For a genuine "median peer's total spending" line,
#'   sum each peer's own categories first and take the quantile of those
#'   per-government totals:
#'
#'   ```r
#'   library(dplyr)
#'   cmp |>
#'     filter(role %in% c("target", "peer")) |>
#'     group_by(year, role, canonical_govid) |>
#'     summarise(total = sum(amt_per_capita_real, na.rm = TRUE), .groups = "drop") |>
#'     filter(role == "peer") |>
#'     group_by(year) |>
#'     summarise(p50 = quantile(total, 0.5, na.rm = TRUE))
#'   ```
#' @section Reading `coverage`:
#' `provenance$coverage` reports `n_units_reporting` against
#' `n_units_expected` per year. **`n_units_reporting` is category-conditional:
#' it counts cohort members with rows for the category you asked for, not
#' cohort members collected that year.** A government that was surveyed and
#' genuinely spends nothing in that category is indistinguishable here from one
#' that was never surveyed.
#'
#' The ratio is therefore **not a response rate** and must not be used as one.
#' In FY2022 — a complete census year — Georgia reports 393 of 567 cities for
#' `category = "Police"`; the 174-city gap is overwhelmingly cities that
#' contract policing to the county sheriff, not non-response.
#'
#' The comparison that *is* valid is the same category across a census year
#' (ending in 2 or 7) and a sample year, where the real-zero component is
#' roughly constant and the difference reflects the survey cycle. `is_census_year`
#' marks which is which.
#' @export
cog_peer_compare <- function(target_govid, peers, category, years,
                             per_capita = TRUE, adjust_to_year = NULL,
                             expenditure_concept = c("primary", "direct", "total"),
                             coverage = c("all", "census", "consistent")) {
  call <- match.call()
  expenditure_concept <- match.arg(expenditure_concept)
  coverage <- .validate_coverage(coverage)
  if (identical(expenditure_concept, "total")) {
    .abort_concept_not_aggregatable("cog_peer_compare")
  }
  if (!is.character(target_govid) || length(target_govid) != 1L) {
    cli::cli_abort("`target_govid` must be a length-1 character string.")
  }
  cohort_year <- if (is.data.frame(peers)) {
    ay <- attr(peers, "cohort_year")
    if (is.null(ay)) NA_integer_ else as.integer(ay)
  } else {
    NA_integer_
  }
  pop_range <- if (is.data.frame(peers)) attr(peers, "pop_range") else NULL
  is_ratio  <- if (is.data.frame(peers)) attr(peers, "is_ratio")  else NULL
  peer_govids <- if (is.data.frame(peers)) {
    as.character(peers$canonical_govid)
  } else {
    as.character(peers)
  }
  peer_govids <- peer_govids[!is.na(peer_govids) & nzchar(peer_govids)]
  all_govids <- unique(c(target_govid, peer_govids))

  years <- .apply_census_years(years, coverage, "cog_peer_compare")

  r <- cog_spending(all_govids, years, category, per_capita, adjust_to_year,
                    expenditure_concept = expenditure_concept)
  r$role <- ifelse(r$canonical_govid == target_govid, "target", "peer")

  # The target is exempt from balancing: it is the subject of the comparison,
  # not a member of the cohort being balanced, and dropping it would leave a
  # peer comparison with nothing to compare. Filtering happens BEFORE the
  # quantiles below, so a "consistent" cohort's summary rows describe that
  # cohort rather than the unbalanced one.
  if (identical(coverage, "consistent")) {
    r <- .filter_consistent(r, years, keep_ids = target_govid)
  }

  value_col <- .peer_value_col(per_capita, adjust_to_year)

  summary_rows <- .peer_summary_rows(r, value_col)
  out <- dplyr::bind_rows(r, summary_rows)
  rank_val <- .peer_target_rank(r, target_govid, years, value_col)
  out$target_rank <- ifelse(out$role == "target", rank_val, NA_integer_)
  out$cohort_year <- cohort_year

  prov <- attr(r, "provenance") %||% list()
  prov$verb        <- "cog_peer_compare"
  prov$call        <- paste(deparse(call), collapse = " ")
  prov$peer_count  <- length(peer_govids)
  prov$cohort_year <- cohort_year
  prov$cohort_govids <- peer_govids
  prov$pop_range   <- pop_range
  prov$is_ratio    <- is_ratio
  prov$target     <- list(
    canonical_govid = target_govid,
    gov_name        = unique(r$gov_name[r$role == "target"])
  )
  # Counted over PEER rows only, against the cohort size: "3 of your 15 peers
  # reported in FY2019". Including the target would inflate every count by one
  # and make a cohort that has entirely stopped reporting look non-empty.
  prov$coverage_mode <- coverage
  prov$coverage <- .coverage_table(
    out, years, length(peer_govids),
    rows = r[r$role == "peer", , drop = FALSE]
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
