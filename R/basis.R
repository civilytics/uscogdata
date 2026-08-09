# R/basis.R
# basis= resolution (harmonized/raw, with v4/v5 dual-accept) and the
# harmonization exclusion-count block attached to provenance.

#' Resolve the requested `basis` against the active corpus's schema_version.
#'
#' On a `schema_version >= 5` corpus, the requested basis is used as-is. On
#' an older (`schema_version == 4`) corpus, which has no harmonization
#' tables: a caller who left `basis` at its default (`"harmonized"`, so
#' `explicit` is `FALSE`) silently gets `"raw"` back, with a note recorded
#' for provenance; a caller who explicitly asked for
#' `basis = "harmonized"` gets a hard abort instead of a silent downgrade.
#'
#' @param basis `"harmonized"` or `"raw"` (already resolved via `match.arg`).
#' @param explicit `TRUE` if the caller passed `basis` explicitly (as
#'   opposed to relying on the default `c("harmonized", "raw")`).
#' @param manifest The active session's parsed manifest list.
#' @return List with `basis` (the resolved value) and `note` (character or
#'   `NA_character_`).
#' @noRd
.resolve_basis <- function(basis, explicit, manifest) {
  schema_version <- suppressWarnings(as.integer(manifest$schema_version %||% 0L))

  if (schema_version >= 5L) {
    return(list(basis = basis, note = NA_character_))
  }

  if (identical(basis, "harmonized") && explicit) {
    cli::cli_abort(c(
      "basis = \"harmonized\" requires corpus schema_version >= 5.",
      x = "Active corpus has schema_version {schema_version}.",
      i = "Use basis = \"raw\" (the default on this corpus), or point USCOGDATA_URL at a schema_version >= 5 corpus."
    ), class = "uscogdata_basis_unsupported")
  }

  list(
    basis = "raw",
    note = sprintf(
      "basis resolved to \"raw\": corpus schema_version %d < 5 (harmonization tables unavailable)",
      schema_version
    )
  )
}

#' Count + sum item-level rows that basis="harmonized" excludes because they
#' carry no harmonized_code (discontinued / not-yet-ruled codes) within the
#' calling verb's crosswalk scope (`subtype_col` values in `subtype_scope` --
#' the same subtype-membership classification the verb SQL uses, never
#' item-code prefixes), govids, and years. Only meaningful when the resolved
#' basis is "harmonized"; returns an applied = FALSE stub otherwise (raw
#' basis never excludes rows this way).
#'
#' The intergovernmental leg is deliberately outside this count even for
#' expenditure_concept = "total": ig_long_harmonized COALESCEs rather than
#' drops NULL-harmonized rows, so harmonization never excludes an IG row.
#' @noRd
.build_harmonization_block <- function(con, cohort, years, resolved,
                                       subtype_col, subtype_scope) {
  if (!identical(resolved$basis, "harmonized")) {
    return(list(
      applied = FALSE,
      na_rows_excluded = 0L,
      na_amount_excluded = 0,
      note = resolved$note
    ))
  }

  sql <- sprintf(
    "SELECT COUNT(*) AS n, COALESCE(SUM(amt), 0) * 1000.0 AS amt
     FROM long
     WHERE %s AND year IN (%s)
       AND NOT is_aggregate AND harmonized_code IS NULL
       AND item_code IN (
         SELECT item_code FROM summary_categories WHERE %s IN (%s)
       )",
    .cohort_sql(cohort), paste(as.integer(years), collapse = ","),
    subtype_col, .sql_lit_chr(subtype_scope)
  )
  na <- DBI::dbGetQuery(con, sql)

  list(
    applied = TRUE,
    na_rows_excluded = as.integer(na$n),
    na_amount_excluded = as.numeric(na$amt),
    note = resolved$note
  )
}
