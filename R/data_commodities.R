# Commodity prices from two sources, for Module 08.
#
# World Bank "Pink Sheet" (CMO Historical Data Monthly): monthly AVERAGE prices
#   in nominal USD, CC BY 4.0, no key. Raw file: data/raw/worldbank/.
# FRED (Federal Reserve Bank of St. Louis) via fredr: daily spot prices, so
#   true month-end values. Needs a free API key in the FRED_API_KEY environment
#   variable (never committed).

#' Read selected series from the Pink Sheet "Monthly Prices" sheet.
#' @return long tibble: month (first of month), series, price
read_pinksheet <- function(path, series = c("Crude oil, Brent", "Crude oil, WTI",
                                            "Crude oil, Dubai", "Iron ore, cfr spot")) {
  raw <- readxl::read_excel(path, sheet = "Monthly Prices", col_names = FALSE, .name_repair = "minimal")
  hdr_row <- which(raw[[2]] == "Crude oil, average")[1]
  names_ <- as.character(unlist(raw[hdr_row, ]))
  dat <- raw[(hdr_row + 2):nrow(raw), ]
  stopifnot(all(series %in% names_))
  out <- lapply(series, function(s) {
    tibble::tibble(month = as.Date(paste0(sub("M", "-", dat[[1]]), "-01")),
                   series = s,
                   price = suppressWarnings(as.numeric(dat[[which(names_ == s)[1]]])))
  })
  dplyr::bind_rows(out) |> dplyr::filter(!is.na(month), !is.na(price))
}

#' Daily FRED series aggregated to month-end and monthly-average prices.
#' @return tibble: month, series_id, price_end, price_avg, n_days
get_fred_monthly <- function(series_id, from = "2010-01-01") {
  key <- Sys.getenv("FRED_API_KEY")
  if (!nzchar(key)) stop("Set FRED_API_KEY (free key from fredaccount.stlouisfed.org/apikey).")
  fredr::fredr_set_key(key)
  x <- fredr::fredr(series_id = series_id, observation_start = as.Date(from))
  x |>
    dplyr::filter(!is.na(value)) |>
    dplyr::mutate(month = lubridate::floor_date(date, "month")) |>
    dplyr::group_by(series_id, month) |>
    dplyr::summarise(price_end = value[which.max(date)], price_avg = mean(value),
                     n_days = dplyr::n(), .groups = "drop")
}

#' One series from SingStat Table Builder (no key needed).
#' Singapore Open Data Licence. Monthly keys like "2026 Sep" become first-of-month dates.
#' @param resource_id e.g. "M213261" (Import Price Index by 3-digit SITC group)
#' @param series_no   e.g. "333" (crude petroleum)
get_singstat_series <- function(resource_id, series_no) {
  url <- sprintf("https://tablebuilder.singstat.gov.sg/api/table/tabledata/%s?seriesNoORrowNo=%s", resource_id, series_no)
  js <- jsonlite::fromJSON(url, simplifyVector = FALSE)
  rows <- js$Data$row
  if (!length(rows)) stop("no SingStat series ", resource_id, " / ", series_no)
  r <- rows[[1]]
  vals <- vapply(r$columns, function(c) as.character(c$value), "")
  keys <- vapply(r$columns, function(c) as.character(c$key), "")
  tibble::tibble(month = as.Date(paste("01", keys), "%d %Y %b"),
                 value = suppressWarnings(as.numeric(vals)),
                 series = r$rowText, resource_id = resource_id, series_no = series_no,
                 data_last_updated = js$Data$dataLastUpdated) |>
    dplyr::filter(!is.na(month), !is.na(value))
}

#' One table from EMA's Singapore Energy Statistics tidy workbook (annual, ktoe).
#' The workbook (SES_tidy.xlsx) is downloaded manually from EMA and kept in
#' gitignored data/raw/ema/; column names are trimmed.
read_ema_ses <- function(path, sheet) {
  d <- readxl::read_excel(path, sheet = sheet)
  names(d) <- trimws(names(d))
  d
}
