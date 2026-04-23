# data-raw/cpi_annual.R
#
# Refresh the bundled CPIAUCSL annual-average table from FRED.
# Run interactively when the CPI series needs to be extended forward:
#   Rscript data-raw/cpi_annual.R
#
# Source: FRED series CPIAUCSL (Consumer Price Index for All Urban Consumers,
# All Items, 1982-84 = 100), monthly. Annual mean computed here. The bundled
# artifact is R/sysdata.rda (loaded automatically by the package).

stopifnot(requireNamespace("utils", quietly = TRUE),
          requireNamespace("tibble", quietly = TRUE),
          requireNamespace("usethis", quietly = TRUE))

fred_url <- "https://fred.stlouisfed.org/graph/fredgraph.csv?id=CPIAUCSL"
raw <- utils::read.csv(url(fred_url), stringsAsFactors = FALSE)
date_col <- intersect(c("observation_date", "DATE", "date"), names(raw))[1]
stopifnot(length(date_col) == 1L, !is.na(date_col))
raw$year <- as.integer(format(as.Date(raw[[date_col]]), "%Y"))
raw$CPIAUCSL <- suppressWarnings(as.numeric(raw$CPIAUCSL))
raw <- raw[!is.na(raw$CPIAUCSL), ]

annual <- stats::aggregate(
  raw$CPIAUCSL, by = list(year = raw$year), FUN = mean, na.rm = TRUE
)
names(annual)[2] <- "cpi"

cpi_annual <- tibble::as_tibble(annual)
cpi_annual$cpi <- round(cpi_annual$cpi, 4)

message(sprintf("CPI range: %d-%d (%d years)",
                min(cpi_annual$year), max(cpi_annual$year), nrow(cpi_annual)))

usethis::use_data(cpi_annual, internal = TRUE, overwrite = TRUE)
