# R/explain.R

#' Explain a verb result's provenance
#'
#' Prints the structured provenance attached to a tibble returned by any
#' `cog_*` verb, or returns it as a list for downstream use (MCP tools,
#' dashboards, JSON export).
#'
#' @param result A tibble returned by a `cog_*` verb.
#' @param format `"print"` (default) for a human-readable cli summary;
#'   returns `result` invisibly for chaining. `"list"` returns the raw
#'   provenance list (identical to `attr(result, "provenance")`).
#' @return Either `result` (invisibly) or the provenance list.
#' @export
cog_explain <- function(result, format = c("print", "list")) {
  format <- match.arg(format)
  prov <- attr(result, "provenance")
  if (is.null(prov)) {
    cli::cli_abort(c(
      "No `provenance` attribute on result.",
      i = "Pass a tibble returned by a cog_* verb (e.g. cog_spending())."
    ))
  }
  if (format == "list") return(prov)
  .print_provenance(prov)
  invisible(result)
}

#' @noRd
.print_provenance <- function(prov) {
  cli::cli_h1("{prov$verb}()")

  tgt_ids   <- paste(prov$target$canonical_govid, collapse = ", ")
  tgt_names <- if (length(prov$target$gov_name) == 0L) {
    "(no rows returned)"
  } else {
    paste(prov$target$gov_name, collapse = ", ")
  }
  cli::cli_text("Target: {tgt_names} [canonical_govid: {tgt_ids}]")

  yrs <- prov$years
  cli::cli_text(if (length(yrs) == 1L) {
    "Year: {yrs}"
  } else {
    "Years: {min(yrs)}-{max(yrs)} ({length(yrs)} years)"
  })

  if (!is.null(prov$category)) {
    cli::cli_text("Category: {paste(prov$category, collapse = ', ')}")
  } else {
    cli::cli_text("Category: (all)")
  }

  if (!is.null(prov$basis)) {
    note <- if (!is.null(prov$basis_note) && !is.na(prov$basis_note)) {
      sprintf(" (%s)", prov$basis_note)
    } else {
      ""
    }
    cli::cli_text("Basis: {prov$basis}{note}")
  }

  # Each verb reports its OWN concept. Both fields are always present (each
  # defaults to its concept's default), so printing `expenditure_concept`
  # unconditionally would tell a cog_revenue() caller "Concept: primary",
  # which names a spending concept their result has nothing to do with.
  if (identical(prov$verb, "cog_revenue")) {
    if (!is.null(prov$revenue_concept)) {
      cli::cli_text("Concept: {prov$revenue_concept} revenue")
    }
  } else if (identical(prov$verb, "cog_balances")) {
    # Both concept fields are deliberately NA here (a stock has no flow
    # concept). Printing the raw NA reads as a missing value rather than an
    # intentional one, so say what it means instead.
    cli::cli_text("Concept: not applicable (holdings are a stock, not a flow)")
  } else if (!is.null(prov$expenditure_concept)) {
    concept_note <- if (!is.null(prov$expenditure_concept_note) &&
                         !is.na(prov$expenditure_concept_note)) {
      sprintf(" (%s)", prov$expenditure_concept_note)
    } else {
      ""
    }
    cli::cli_text("Concept: {prov$expenditure_concept}{concept_note}")
    if (isTRUE(prov$expenditure_concept_direct_suppressed)) {
      cli::cli_alert_warning(
        "Direct leg unavailable for at least one requested (year, category) -- affected rows report intergovernmental dollars alone, not Direct + IG. See each row's notes."
      )
    }
  }

  cli::cli_h2("Codes observed")
  codes <- prov$codes_summed$observed
  if (length(codes) == 0L) {
    cli::cli_alert_info("No item codes matched.")
  } else {
    cli::cli_ul(codes)
  }

  if (isTRUE(prov$aggregate_fallback$applied)) {
    cli::cli_h2("Aggregate fallback")
    cli::cli_alert_warning(
      "Aggregate fallback used for years: {paste(prov$aggregate_fallback$years, collapse = ', ')}"
    )
  }

  h <- prov$harmonization
  if (!is.null(h) && isTRUE(h$applied)) {
    cli::cli_h2("Harmonization")
    cli::cli_text(
      "Excluded {h$na_rows_excluded} row(s) with no harmonized_code (${format(h$na_amount_excluded, big.mark = ',')})"
    )
  }

  rc <- prov$recipe
  if (!is.null(rc)) {
    cli::cli_h2("Recipe")
    cli::cli_text("{rc$recipe_id}: {rc$label}")
    comp_lines <- vapply(rc$components, function(x) {
      sprintf("%s (%s, %s-%s, weight=%s)", x$component_code, x$gov_type_scope,
              x$year_min, x$year_max, x$weight)
    }, character(1))
    cli::cli_ul(comp_lines)
  }

  if (length(prov$suggestions) > 0L) {
    cli::cli_h2("Suggestions")
    sugg_lines <- vapply(prov$suggestions, function(s) {
      line <- sprintf("%s -- %s (years %s-%s): %s", s$recipe_id, s$label,
              s$available_years[1], s$available_years[2], s$hint)
      if (isTRUE(s$suppressed_amount > 0)) {
        line <- paste0(line, sprintf(" [$%s excluded from %s: %s]",
          formatC(s$suppressed_amount, format = "f", digits = 0, big.mark = ","),
          paste0("FY", s$suppressed_years, collapse = ", "),
          paste(s$suppressed_codes, collapse = ", ")))
      }
      line
    }, character(1))
    cli::cli_ul(sugg_lines)
  }

  if (!is.null(prov$coverage) && nrow(prov$coverage) > 0L) {
    cli::cli_h2("Reporting coverage")
    cli::cli_text("Mode: {prov$coverage_mode %||% 'all'}")
    cov <- prov$coverage
    cli::cli_ul(sprintf(
      "%d: %d of %d units reporting (%.0f%%) -- %s year",
      cov$year, cov$n_units_reporting, cov$n_units_expected,
      100 * cov$n_units_reporting / pmax(cov$n_units_expected, 1L),
      ifelse(cov$is_census_year, "census", "sample")
    ))
    if (any(!cov$is_census_year)) {
      cli::cli_text(
        "Note: the Census of Governments is a complete census only in years ending in 2 or 7; every other year is a sample."
      )
    }
  }

  if (isTRUE(prov$completion$applied)) {
    cli::cli_h2("Completion")
    cli::cli_text(
      "Filled {prov$completion$rows_filled} absent cell(s) from the corpus code set."
    )
    rules <- prov$completion$absence_means
    if (length(rules) > 0L) {
      cli::cli_ul(vapply(names(rules), function(y) {
        sprintf("%s: an absent cell means %s", y,
                if (identical(rules[[y]], "census_zero")) {
                  "Census published $0 (filled as 0)"
                } else {
                  "the government did not report (filled as NA, not 0)"
                })
      }, character(1)))
    }
  }

  if (length(prov$series_break_refs) > 0L) {
    cli::cli_h2("Series breaks")
    cli::cli_ul(.series_break_story_lines(prov$series_break_refs))
  }

  # Kept in a section of its own: these qualify the whole result, so folding
  # them in with the per-code breaks above would invite reading them as a
  # caveat about one series.
  if (length(prov$corpus_break_refs) > 0L) {
    cli::cli_h2("Corpus-wide caveats")
    cli::cli_ul(.series_break_story_lines(prov$corpus_break_refs))
  }

  # Balance results only (NULL on money-verb provenance, so they are
  # unaffected). This is the ONLY on-demand surface for the GAAP disclosure:
  # .emit_balance_caveats() fires at most once per session, and is routinely
  # consumed by a suppressMessages() call or by a knitted chunk nobody reads,
  # so a caller who deliberately audits a result with cog_explain() must still
  # be told.
  bc <- prov$balance_caveats
  if (!is.null(bc)) {
    cli::cli_h2("Holdings caveats")
    if (!is.null(bc$not_gaap_note)) cli::cli_alert_warning(bc$not_gaap_note)
    if (length(bc$truncated) > 0L) {
      cli::cli_text(
        "Requested years extend beyond what these families actually cover:"
      )
      cli::cli_ul(vapply(bc$truncated, function(s) {
        w <- bc$coverage_window[[s]]
        if (length(w) == 2L) {
          sprintf("%s: covered %s-%s in this corpus", s, w[1], w[2])
        } else {
          s
        }
      }, character(1)))
    }
  }

  cli::cli_h2("Transformations")
  uc <- prov$transformations$units_conversion
  if (isTRUE(uc$applied)) {
    cli::cli_text("Units: {uc$source_unit} -> {uc$target_unit} (x{uc$multiplier})")
  }
  pc <- prov$transformations$per_capita
  if (isTRUE(pc$applied)) {
    cli::cli_text("Per-capita denominator: {pc$denominator_source}")
    if (length(pc$popyear_range) == 2L) {
      lo <- .expand_popyear(pc$popyear_range[1])
      hi <- .expand_popyear(pc$popyear_range[2])
      cli::cli_text("  popyear range: {lo}-{hi}")
    }
    if (!is.null(pc$pop_source_counts)) {
      cli::cli_text(
        "  pop_source counts: census_f33={pc$pop_source_counts$census_f33}, unavailable={pc$pop_source_counts$unavailable}"
      )
    }
  }
  infl <- prov$transformations$inflation
  if (isTRUE(infl$applied)) {
    cli::cli_text("Inflation: {infl$index}, base year {infl$base_year}")
  }

  cli::cli_h2("Scope")
  cli::cli_text(
    "Included gov types: {paste(prov$scope$gov_types_included, collapse = ', ')}"
  )
  cli::cli_text(
    "Excluded gov types: {paste(prov$scope$gov_types_excluded, collapse = ', ')}"
  )
  if (nzchar(prov$scope$scope_note %||% "")) {
    cli::cli_text("Note: {prov$scope$scope_note}")
  }

  cli::cli_h2("Data vintage")
  cli::cli_text(
    "Manifest schema v{prov$manifest$schema_version}, pipeline {prov$manifest$pipeline_commit}, built {prov$manifest$built_at}"
  )

  invisible(NULL)
}

# One "break-story" line per referenced break_id: "SB109 (2005): <join_advice>".
# Re-queries series_breaks_pq for the detail (break_year, join_advice) that
# provenance$series_break_refs deliberately doesn't carry (the schema keeps
# that field to a plain id array). Falls back to bare ids if no session is
# available (e.g. explaining a result after cog_close()) rather than
# erroring cog_explain() over a cosmetic detail.
#' @noRd
.series_break_story_lines <- function(break_ids) {
  con <- tryCatch(.ensure_session(), error = function(e) NULL)
  if (is.null(con) || !DBI::dbIsValid(con)) return(break_ids)
  detail <- tryCatch(
    DBI::dbGetQuery(con, sprintf(
      "SELECT break_id, break_year, join_advice FROM series_breaks_pq
       WHERE break_id IN (%s) ORDER BY break_id",
      .sql_lit_chr(break_ids)
    )),
    error = function(e) NULL
  )
  if (is.null(detail) || nrow(detail) == 0L) return(break_ids)
  sprintf("%s (%s): %s", detail$break_id, detail$break_year, detail$join_advice)
}

# Expand a 2-digit Census popyear (e.g. 19) to a 4-digit calendar year (2019).
# F-33 metadata stores popyear as 2 digits; pivot at 70 to handle a future
# corpus that ever spans pre-1970 vintages, though current scope is 2000+.
#' @noRd
.expand_popyear <- function(yy) {
  yy <- as.integer(yy)
  if (length(yy) == 0L || is.na(yy)) return(NA_integer_)
  if (yy >= 100L) return(yy)        # already 4-digit
  if (yy < 70L)  return(2000L + yy)
  1900L + yy
}
