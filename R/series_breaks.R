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
     WHERE fin_code IN (%s) AND break_year BETWEEN %d AND %d
     ORDER BY break_id",
    .sql_lit_chr(codes_observed), min(as.integer(years)), max(as.integer(years))
  )
  DBI::dbGetQuery(con, sql)$break_id
}
