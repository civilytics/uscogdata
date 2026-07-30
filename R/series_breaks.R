# R/series_breaks.R
# Populates prov$series_break_refs (schema in inst/schemas/provenance-v1.json
# defines the field; it was always present but always empty pre-Phase-R2)
# with the ids of any catalogued series break whose fin_code appears among
# the result's observed item codes and whose break_year falls inside the
# requested year span -- the "break warnings in the provenance envelope"
# spec § 5 promises downstream consumers (cog-api passes provenance through
# verbatim). schema_version >= 5 only: series_breaks_pq isn't registered on
# an older corpus.

#' @noRd
.build_series_break_refs <- function(con, codes_observed, years, schema_version) {
  if (schema_version < 5L || length(codes_observed) == 0L) return(character(0))
  sql <- sprintf(
    "SELECT DISTINCT break_id
     FROM series_breaks_pq
     WHERE fin_code IN (%s) AND fin_code <> 'ALL'
       AND break_year BETWEEN %d AND %d
     ORDER BY break_id",
    .sql_lit_chr(codes_observed), min(as.integer(years)), max(as.integer(years))
  )
  DBI::dbGetQuery(con, sql)$break_id
}

#' Corpus-wide caveats: catalogued breaks whose `fin_code` is the literal
#' `"ALL"` rather than an item code. They qualify the whole result, so they
#' cannot be matched the way `.build_series_break_refs()` matches -- no row's
#' `item_code` is ever `"ALL"`, which is exactly why they reached no user
#' before uscogdata#19. Selection is on the break_year window alone: which
#' codes a result happens to contain is irrelevant to a caveat about the
#' corpus.
#'
#' All four catalogued entries are *boundary* caveats (dollar precision
#' across 1976/1977, imputation exclusion from 2002, the dense -> sparse
#' representation change at 2012, the id scheme change at 2017), so the same
#' `break_year BETWEEN min(years) AND max(years)` rule the code-specific
#' path uses is the right one -- a request that never crosses the boundary
#' is not affected by it.
#'
#' Returned separately from `series_break_refs` so a consumer can tell a
#' whole-result caveat from a break in one series; the two are disjoint by
#' construction.
#' @noRd
.build_corpus_break_refs <- function(con, years, schema_version) {
  if (schema_version < 5L || length(years) == 0L) return(character(0))
  sql <- sprintf(
    "SELECT DISTINCT break_id
     FROM series_breaks_pq
     WHERE fin_code = 'ALL' AND break_year BETWEEN %d AND %d
     ORDER BY break_id",
    min(as.integer(years)), max(as.integer(years))
  )
  DBI::dbGetQuery(con, sql)$break_id
}
