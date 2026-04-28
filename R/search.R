# R/search.R

#' Search for governments by name, state, and/or type
#'
#' Two modes:
#'
#' * **Utility mode** (single `name`): returns all rows from
#'   `canonical_fips_xwalk` whose `gov_name` matches the regex
#'   case-insensitively, sorted by `population_acs` descending.
#' * **Basket mode** (`length(name) > 1`): resolves each input row to a
#'   single canonical govid via exact-then-substring matching with
#'   deterministic disambiguation. Returns up to `length(name)` rows in
#'   input order plus a `"resolution"` sidecar attribute. See
#'   [cog_basket_resolution()].
#'
#' @param name Character vector of place name(s). Length 1 = utility mode;
#'   length >1 = basket mode.
#' @param state Either a 2-letter USPS abbreviation, a FIPS integer, or
#'   `NULL`. Length 1 recycles across all entries in basket mode.
#' @param type Government type: an integer in `0:3` or one of `"state"`,
#'   `"county"`, `"city"`, `"township"`, or `NA` (per-row optional in
#'   basket mode). Passing `4`, `5`, `"special_district"`, or
#'   `"school_district"` emits an explanatory message and returns an
#'   empty tibble (v0.1 corpus excludes those types).
#' @return Tibble from `canonical_fips_xwalk`. In utility mode, sorted by
#'   `population_acs` descending (`NULL`s last). In basket mode, in input
#'   order, with `attr(result, "resolution")` set to the sidecar tibble.
#' @export
cog_gov_search <- function(name = NULL, state = NULL, type = NULL) {
  if (!is.null(type) && length(type) == 1L && .is_excluded_type(type)) {
    cli::cli_inform(c(
      i = "v0.1 covers gov_types 0-3 (state/county/city/township) only.",
      i = "Types 4 (special districts) and 5 (school districts) are excluded; see vignette('coverage-scope')."
    ))
    return(.empty_xwalk_tibble())
  }

  con <- .ensure_session()

  if (length(name) > 1L) {
    return(.resolve_basket(name = name, state = state, type = type, con = con))
  }

  preds <- character(0)
  if (!is.null(name)) {
    if (!is.character(name) || length(name) != 1L) {
      cli::cli_abort("`name` must be a length-1 character string.")
    }
    preds <- c(preds,
               sprintf("regexp_matches(gov_name, %s, 'i')",
                       .sql_lit_chr(name)))
  }
  if (!is.null(state)) {
    st_fips <- .coerce_state_to_fips(state)
    preds <- c(preds, sprintf("fips_state = %s", .sql_lit_chr(st_fips)))
  }
  if (!is.null(type)) {
    int_type <- .coerce_type(type)
    preds <- c(preds, sprintf("govs_type = %d", int_type))
  }

  where <- if (length(preds) == 0L) "" else paste("WHERE", paste(preds, collapse = " AND "))
  sql <- paste(
    "SELECT * FROM canonical_fips_xwalk",
    where,
    "ORDER BY population_acs DESC NULLS LAST"
  )
  tibble::as_tibble(DBI::dbGetQuery(con, sql))
}

#' @noRd
.empty_xwalk_tibble <- function() {
  tibble::tibble(
    canonical_govid = character(0), gov_name = character(0),
    govs_type = integer(0), type_label = character(0),
    fips_state = character(0), fips_county = character(0),
    fips_place = character(0), first_year = integer(0),
    last_year = integer(0), population_acs = integer(0),
    confidence = character(0)
  )
}

#' @noRd
.is_excluded_type <- function(type) {
  excluded <- c("4", "5", "special_district", "school_district")
  as.character(type) %in% excluded
}

#' @noRd
.coerce_type <- function(type) {
  if (is.numeric(type) ||
      (is.character(type) && length(type) == 1L && grepl("^[0-9]+$", type))) {
    n <- as.integer(type)
    if (!n %in% 0:3) {
      cli::cli_abort("type must be 0, 1, 2, or 3 (v0.1 scope).")
    }
    return(n)
  }
  map <- c(state = 0L, county = 1L, city = 2L, township = 3L)
  key <- as.character(type)
  if (!key %in% names(map)) cli::cli_abort("Unknown type: {type}.")
  map[[key]]
}

#' @noRd
.coerce_state_to_fips <- function(state) {
  if (is.numeric(state) ||
      (is.character(state) && length(state) == 1L && grepl("^[0-9]+$", state))) {
    return(sprintf("%02d", as.integer(state)))
  }
  if (!is.character(state) || length(state) != 1L) {
    cli::cli_abort("`state` must be a 2-letter USPS abbrev or a FIPS integer.")
  }
  fips <- .state_abbrev_to_fips[[toupper(state)]]
  if (is.null(fips)) {
    cli::cli_abort("Unknown state abbreviation: {state}.")
  }
  fips
}

# USPS state / territory abbreviation -> 2-digit FIPS code.
# Includes 50 states + DC + territories. Note FIPS 66 = GU (not GA).
#' @noRd
.state_abbrev_to_fips <- c(
  AL = "01", AK = "02", AZ = "04", AR = "05", CA = "06", CO = "08",
  CT = "09", DE = "10", DC = "11", FL = "12", GA = "13", HI = "15",
  ID = "16", IL = "17", IN = "18", IA = "19", KS = "20", KY = "21",
  LA = "22", ME = "23", MD = "24", MA = "25", MI = "26", MN = "27",
  MS = "28", MO = "29", MT = "30", NE = "31", NV = "32", NH = "33",
  NJ = "34", NM = "35", NY = "36", NC = "37", ND = "38", OH = "39",
  OK = "40", OR = "41", PA = "42", RI = "44", SC = "45", SD = "46",
  TN = "47", TX = "48", UT = "49", VT = "50", VA = "51", WA = "53",
  WV = "54", WI = "55", WY = "56",
  AS = "60", GU = "66", MP = "69", PR = "72", VI = "78"
)

# Validate basket-mode inputs. Returns a list with normalized character
# vectors `name`, `state`, `type`, all of length n = length(name).
# `state` and `type` of length 1 are recycled; lengths must be 1 or n
# otherwise. NULL state/type become a vector of NA_character_.
#' @noRd
.validate_basket_args <- function(name, state, type) {
  if (!is.character(name)) {
    cli::cli_abort("`name` must be a character vector.")
  }
  n <- length(name)

  state_norm <- if (is.null(state)) {
    rep(NA_character_, n)
  } else if (length(state) == 1L) {
    rep(as.character(state), n)
  } else if (length(state) == n) {
    as.character(state)
  } else {
    cli::cli_abort(
      "`state` must be length 1 or {n} (length of `name`); got {length(state)}."
    )
  }

  type_norm <- if (is.null(type)) {
    rep(NA_character_, n)
  } else if (length(type) == 1L) {
    rep(as.character(type), n)
  } else if (length(type) == n) {
    as.character(type)
  } else {
    cli::cli_abort(
      "`type` must be length 1 or {n} (length of `name`); got {length(type)}."
    )
  }

  list(name = name, state = state_norm, type = type_norm)
}

# Resolve a single basket-mode input row. Returns a list with components:
#   status        : "resolved" | "largest_pop" | "ambiguous" | "no_match"
#   match_method  : "exact" | "substring" | NA_character_
#   n_candidates  : int
#   row           : tibble (single resolved row, or 0-row tibble for unresolved)
#   candidates    : tibble (all rows that matched, for sidecar)
# Internal use only; takes an active DuckDB connection to reuse the session.
#' @noRd
.resolve_basket_row <- function(name, state, type, con) {
  # Short-circuit: empty/whitespace name -> no_match without SQL.
  if (!nzchar(trimws(name))) {
    empty <- .empty_xwalk_tibble()
    return(list(
      status       = "no_match",
      match_method = NA_character_,
      n_candidates = 0L,
      row          = empty,
      candidates   = empty
    ))
  }

  preds <- character(0)
  if (!is.na(state)) {
    st_fips <- .coerce_state_to_fips(state)
    preds <- c(preds, sprintf("fips_state = %s", .sql_lit_chr(st_fips)))
  }
  if (!is.na(type)) {
    int_type <- .coerce_type(type)
    preds <- c(preds, sprintf("govs_type = %d", int_type))
  }
  base_where <- if (length(preds) == 0L) "" else paste("WHERE", paste(preds, collapse = " AND "))
  conj <- if (nzchar(base_where)) "AND" else "WHERE"

  exact_sql <- paste(
    "SELECT * FROM canonical_fips_xwalk",
    base_where,
    conj,
    sprintf("LOWER(gov_name) = LOWER(%s)", .sql_lit_chr(name))
  )
  exact <- tibble::as_tibble(DBI::dbGetQuery(con, exact_sql))

  if (nrow(exact) == 1L) {
    return(list(
      status       = "resolved",
      match_method = "exact",
      n_candidates = 1L,
      row          = exact,
      candidates   = exact
    ))
  }
  if (nrow(exact) > 1L) {
    return(.disambiguate(exact, method = "exact"))
  }

  sub_sql <- paste(
    "SELECT * FROM canonical_fips_xwalk",
    base_where,
    conj,
    sprintf("regexp_matches(gov_name, %s, 'i')", .sql_lit_chr(name))
  )
  sub <- tibble::as_tibble(DBI::dbGetQuery(con, sub_sql))

  if (nrow(sub) == 0L) {
    return(list(
      status       = "no_match",
      match_method = NA_character_,
      n_candidates = 0L,
      row          = sub,
      candidates   = sub
    ))
  }
  if (nrow(sub) == 1L) {
    return(list(
      status       = "resolved",
      match_method = "substring",
      n_candidates = 1L,
      row          = sub,
      candidates   = sub
    ))
  }
  .disambiguate(sub, method = "substring")
}

# Disambiguate a multi-row match set. Either picks the largest-pop row
# (within single-type) or returns an ambiguous result with no basket row.
#' @noRd
.disambiguate <- function(matches, method) {
  types <- unique(matches$govs_type)
  if (length(types) == 1L) {
    pick <- matches[order(-matches$population_acs, na.last = TRUE), , drop = FALSE][1L, , drop = FALSE]
    return(list(
      status       = "largest_pop",
      match_method = method,
      n_candidates = nrow(matches),
      row          = pick,
      candidates   = matches
    ))
  }
  empty <- matches[0, , drop = FALSE]
  list(
    status       = "ambiguous",
    match_method = NA_character_,
    n_candidates = nrow(matches),
    row          = empty,
    candidates   = matches
  )
}

# Orchestrates basket-mode resolution: validate, per-row resolve,
# assemble the basket tibble + sidecar, attach the sidecar as an attr.
# Caller is responsible for emitting any post-resolution summary message
# (see Task 7 — this stays silent for now).
#' @noRd
.resolve_basket <- function(name, state, type, con) {
  args <- .validate_basket_args(name = name, state = state, type = type)
  n <- length(args$name)

  resolved <- vector("list", n)
  for (i in seq_len(n)) {
    resolved[[i]] <- .resolve_basket_row(
      name  = args$name[i],
      state = args$state[i],
      type  = args$type[i],
      con   = con
    )
  }

  basket_rows <- lapply(resolved, function(r) r$row)
  basket <- dplyr::bind_rows(basket_rows[vapply(basket_rows, function(r) nrow(r) > 0L, logical(1))])
  if (nrow(basket) == 0L) basket <- .empty_xwalk_tibble()

  sidecar <- .build_sidecar(args, resolved)
  attr(basket, "resolution") <- sidecar
  basket
}

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
  c("0" = "state", "1" = "county", "2" = "city", "3" = "township")[[as.character(int_type)]]
}
