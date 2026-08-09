# How a verb names the set of governments it queries.
#
# Historically there was one way: a `govid` character vector, rendered by
# .sql_lit_chr() into a quoted IN list. That is fine for a handful of
# governments and pathological for a fleet. Measured against the production
# corpus, the same FY2022 aggregate over the 20,106-government `type = "city"`
# cohort:
#
#   cohort expressed as                            time
#   IN (20,106 literals)                           449 ms
#   join against a temp cohort table                99 ms
#   predicate on canonical_fips_xwalk               94 ms
#   no cohort filter at all (the floor)             88 ms
#
# 4.8x, and within 7% of the no-filter floor. The rendered IN list is 301,591
# characters and .verb_spendrev() embeds it in 5-8 separate statements per
# call, so the parse-and-plan cost is paid over and over (uscogdata#58).
#
# A cohort therefore has two independent halves, and a query can carry either
# or both:
#
#   ids        an explicit canonical_govid vector      -> literal IN list
#   predicate  state/type over canonical_fips_xwalk    -> IN (SELECT ...)
#
# Both together is an INTERSECTION -- "these ids, narrowed to that state/type"
# -- never a precedence rule where one silently wins.

#' Build the internal cohort object shared by every query verb.
#'
#' `state` and `type` are coerced with the SAME helpers `cog_gov_search()`
#' uses. That is load-bearing, not tidiness: the public argument is a postal
#' abbreviation (`"WI"`) while `canonical_fips_xwalk.fips_state` holds a FIPS
#' code (`"55"`), and `type` is a label (`"city"`) against an integer
#' `govs_type`. A predicate written against the raw parameter matches nothing
#' and returns an empty result indistinguishable from "this government
#' reported nothing" -- cog-api hit exactly that trap optimizing this path.
#' One definition of the translation, not two.
#'
#' @param govid Already-coerced character vector of canonical_govids, or NULL.
#' @param state Postal abbreviation or FIPS code, or NULL.
#' @param type Type label or integer code, or NULL.
#' @noRd
.make_cohort <- function(govid = NULL, state = NULL, type = NULL) {
  if (is.null(govid) && is.null(state) && is.null(type)) {
    cli::cli_abort(c(
      "A cohort must be named.",
      "*" = "Pass {.arg govid} for specific governments, or {.arg state}/{.arg type} for every government matching a predicate.",
      "i" = "Passing both intersects them: the governments in {.arg govid} that also match {.arg state}/{.arg type}."
    ), class = "uscogdata_no_cohort")
  }
  structure(
    list(
      ids        = govid,
      state      = state,
      type       = type,
      state_fips = if (is.null(state)) NULL else .coerce_state_to_fips(state),
      type_int   = if (is.null(type)) NULL else .coerce_type(type)
    ),
    class = "uscogdata_cohort"
  )
}

#' Is any part of this cohort expressed as an xwalk predicate?
#' @noRd
.cohort_by_predicate <- function(cohort) {
  !is.null(cohort$state_fips) || !is.null(cohort$type_int)
}

#' Render the cohort as a SQL boolean expression over `col`.
#'
#' `col` may be qualified (`"l.canonical_govid"`, `"x.canonical_govid"`) --
#' several call sites join the xwalk under an alias. The subquery's own
#' projected column stays unqualified: it selects from canonical_fips_xwalk,
#' not from the outer relation.
#' @noRd
.cohort_sql <- function(cohort, col = "canonical_govid") {
  preds <- character(0)

  if (!is.null(cohort$ids)) {
    preds <- c(preds, sprintf("%s IN (%s)", col, .sql_lit_chr(cohort$ids)))
  }

  if (.cohort_by_predicate(cohort)) {
    xwalk_preds <- character(0)
    if (!is.null(cohort$state_fips)) {
      xwalk_preds <- c(xwalk_preds,
                       sprintf("fips_state = %s", .sql_lit_chr(cohort$state_fips)))
    }
    if (!is.null(cohort$type_int)) {
      xwalk_preds <- c(xwalk_preds, sprintf("govs_type = %d", cohort$type_int))
    }
    preds <- c(preds, sprintf(
      "%s IN (SELECT canonical_govid FROM canonical_fips_xwalk WHERE %s)",
      col, paste(xwalk_preds, collapse = " AND ")
    ))
  }

  paste(preds, collapse = " AND ")
}

#' How many governments the cohort covers.
#'
#' One COUNT against the crosswalk, used only to populate the provenance
#' `scope$cohort` block. Deliberately a count rather than the id list: a
#' fleet-scale cohort would otherwise put 20,000 ids into every response body,
#' which is the cost this issue exists to remove.
#' @noRd
.cohort_count <- function(con, cohort) {
  sql <- sprintf(
    "SELECT COUNT(*) AS n FROM canonical_fips_xwalk WHERE %s",
    .cohort_sql(cohort)
  )
  as.integer(DBI::dbGetQuery(con, sql)$n[[1]])
}

#' The provenance `scope$cohort` block for a predicate cohort, or NULL when
#' the cohort was named by id alone (in which case `govids_found`/
#' `govids_missing` already describe it exactly).
#' @noRd
.cohort_provenance <- function(con, cohort) {
  if (!.cohort_by_predicate(cohort)) return(NULL)
  list(
    state         = if (is.null(cohort$state)) NA_character_ else as.character(cohort$state),
    type          = if (is.null(cohort$type)) NA_character_ else as.character(cohort$type),
    n_governments = .cohort_count(con, cohort)
  )
}
