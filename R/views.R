# R/views.R

#' Register DuckDB views from inst/sql/ SQL files
#' @noRd
.register_views <- function(con, url, manifest) {
  sql_dir <- system.file("sql", package = "uscogdata")
  files   <- list.files(sql_dir, pattern = "\\.sql$", full.names = TRUE)
  for (f in files) {
    sql <- paste(readLines(f, warn = FALSE), collapse = "\n")
    sql <- gsub("\\{url\\}", url, sql, fixed = FALSE)
    DBI::dbExecute(con, sql)
  }
}
