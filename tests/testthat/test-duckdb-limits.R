# tests/testthat/test-duckdb-limits.R
#
# uscogdata#60. cog_open() used to connect with a bare dbConnect() and set no
# resource pragmas, so DuckDB claimed every visible core. That is right for one
# interactive session on a dedicated machine and wrong for a server: cog-api
# runs two replicas on an 8-core host budgeted 4, and without a cap each
# replica independently claims all 8 and they fight.
#
# The consumer-side workaround this replaces reached into the namespace at
# boot -- getFromNamespace(".ensure_session", "uscogdata")() followed by a
# manual SET threads -- which depends on a private name AND on the session
# already being open.
#
# The load-bearing property is the NEGATIVE one: unset must emit no pragma at
# all, so an unconfigured session is byte-identical to pre-#60 behaviour.

# Open a session under a given configuration and read a DuckDB setting back.
# Each call closes first, because both settings are session-scoped: an
# already-open connection would be reused by .ensure_session() and report the
# PREVIOUS test's value, which is exactly the false pass to avoid here.
setting_under <- function(setting, envvars = character(0), opts = list()) {
  uscogdata:::cog_close()
  on.exit(uscogdata:::cog_close(), add = TRUE)
  withr::with_envvar(envvars, {
    withr::with_options(opts, {
      con <- uscogdata:::cog_open()
      DBI::dbGetQuery(
        con, sprintf("SELECT current_setting('%s') AS v", setting)
      )$v[[1]]
    })
  })
}

test_that("USCOGDATA_DUCKDB_THREADS caps the connection's thread count", {
  skip_if_no_corpus()
  expect_equal(
    as.integer(setting_under("threads", c(USCOGDATA_DUCKDB_THREADS = "2"))),
    2L
  )
})

test_that("the option spelling works, and the env var beats it", {
  skip_if_no_corpus()
  expect_equal(
    as.integer(setting_under("threads",
                             c(USCOGDATA_DUCKDB_THREADS = NA),
                             list(uscogdata.duckdb_threads = 3L))),
    3L
  )
  # Same precedence .cfg() gives every other setting: env var > option.
  expect_equal(
    as.integer(setting_under("threads",
                             c(USCOGDATA_DUCKDB_THREADS = "1"),
                             list(uscogdata.duckdb_threads = 3L))),
    1L
  )
})

test_that("unset leaves DuckDB's own default in place", {
  skip_if_no_corpus()
  # Not asserting a specific number -- the default is core-count-dependent and
  # a literal would fail on a different machine. The claim is that NO pragma
  # was issued, so the session sees whatever DuckDB would have chosen on its
  # own. Compared against a plain connection opened the pre-#60 way.
  unset <- setting_under("threads",
                         c(USCOGDATA_DUCKDB_THREADS = NA),
                         list(uscogdata.duckdb_threads = NULL))
  bare <- local({
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    DBI::dbGetQuery(con, "SELECT current_setting('threads') AS v")$v[[1]]
  })
  expect_equal(as.integer(unset), as.integer(bare))
})

test_that("USCOGDATA_DUCKDB_MEMORY_LIMIT is applied", {
  skip_if_no_corpus()
  v <- setting_under("memory_limit", c(USCOGDATA_DUCKDB_MEMORY_LIMIT = "2GB"))
  # DuckDB does not echo back the string it was given: it stores bytes and
  # reports BINARY units, so "2GB" (2e9 bytes) comes back as "1.8 GiB". Assert
  # the magnitude it actually means rather than the spelling this package sent
  # -- matching on "2" passes for the wrong reason and fails on the right one.
  expect_match(as.character(v), "GiB", fixed = TRUE)
  # DuckDB also truncates the display to one decimal ("1.8 GiB" for 1.863), so
  # the tolerance covers rounding, not slack in the setting itself.
  gib <- as.numeric(sub("\\s*GiB$", "", as.character(v)))
  expect_equal(gib, 2e9 / 1024^3, tolerance = 0.05)
})

# --- Validation -------------------------------------------------------------
# .cfg() returns an env var as CHARACTER. Without coercion here,
# sprintf("SET threads TO %d", "4") aborts inside the connection path with an
# error about the pragma rather than about the setting the operator got wrong.

test_that(".resolve_duckdb_threads coerces a character env var to integer", {
  withr::local_envvar(USCOGDATA_DUCKDB_THREADS = "4")
  expect_identical(uscogdata:::.resolve_duckdb_threads(), 4L)
})

test_that(".resolve_duckdb_threads returns NULL when unset or empty", {
  withr::local_options(uscogdata.duckdb_threads = NULL)
  withr::local_envvar(USCOGDATA_DUCKDB_THREADS = NA)
  expect_null(uscogdata:::.resolve_duckdb_threads())

  withr::local_envvar(USCOGDATA_DUCKDB_THREADS = "")
  expect_null(uscogdata:::.resolve_duckdb_threads())
})

test_that(".resolve_duckdb_threads rejects values that are not positive integers", {
  for (bad in c("0", "-1", "two", "1.5.2")) {
    withr::local_envvar(USCOGDATA_DUCKDB_THREADS = bad)
    expect_error(uscogdata:::.resolve_duckdb_threads(),
                 class = "uscogdata_invalid_duckdb_threads")
  }
})

test_that(".resolve_duckdb_memory_limit accepts size strings and rejects junk", {
  withr::local_envvar(USCOGDATA_DUCKDB_MEMORY_LIMIT = "4GB")
  expect_identical(uscogdata:::.resolve_duckdb_memory_limit(), "4GB")

  withr::local_envvar(USCOGDATA_DUCKDB_MEMORY_LIMIT = "1.5GB")
  expect_identical(uscogdata:::.resolve_duckdb_memory_limit(), "1.5GB")

  # A SQL fragment must not reach the connection as one.
  withr::local_envvar(USCOGDATA_DUCKDB_MEMORY_LIMIT = "4GB'; DROP TABLE x; --")
  expect_error(uscogdata:::.resolve_duckdb_memory_limit(),
               class = "uscogdata_invalid_duckdb_memory_limit")
})

test_that(".apply_duckdb_limits issues no statement when both are NULL", {
  # The negative property, asserted directly rather than inferred: a connection
  # that would ERROR on any statement proves none was sent.
  expect_silent(uscogdata:::.apply_duckdb_limits(NULL, NULL, NULL))
})
