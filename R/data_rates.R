# Risk-free rates, one per market, each in its own currency.
#
# Each function returns a tibble (month, rf_annual_pct): the rate observed for
# that calendar month. Rates are converted to a monthly return and lagged one
# month by rf_monthly(), so the rate known at the end of month t-1 is the
# risk-free return for month t.

#' Australia: RBA table F1, end-of-day 1-month bank accepted bills (BABs/NCDs),
#' month-end observation.
get_rf_au <- function() {
  url <- "https://www.rba.gov.au/statistics/tables/csv/f1-data.csv"
  tmp <- tempfile(fileext = ".csv")
  utils::download.file(url, tmp, quiet = TRUE, mode = "wb",
                       headers = c("User-Agent" = "Mozilla/5.0"))
  lines <- readLines(tmp, encoding = "UTF-8", warn = FALSE)
  hdr <- strsplit(lines[grep("^Title,", lines)[1]], ",")[[1]]
  col <- which(trimws(hdr) == "EOD 1-month BABs/NCDs")
  stopifnot(length(col) == 1)
  data_lines <- grep("^\\d{2}-[A-Za-z]{3}-\\d{4},", lines, value = TRUE)
  fields <- strsplit(data_lines, ",", fixed = TRUE)
  tibble::tibble(
    date = as.Date(vapply(fields, `[`, "", 1), "%d-%b-%Y"),
    rate = suppressWarnings(as.numeric(vapply(fields, function(f) if (length(f) >= col) f[col] else NA_character_, "")))
  ) |>
    dplyr::filter(!is.na(rate)) |>
    dplyr::mutate(month = lubridate::floor_date(date, "month")) |>
    dplyr::group_by(month) |>
    dplyr::slice_max(date, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::transmute(month, rf_annual_pct = rate, market = "ASX")
}

#' Hong Kong: HKMA monthly statistical bulletin, 1-month HIBOR, end of month.
get_rf_hk <- function() {
  url <- paste0("https://api.hkma.gov.hk/public/market-data-and-statistics/",
                "monthly-statistical-bulletin/er-ir/hk-interbank-ir-endperiod",
                "?pagesize=1000&sortby=end_of_month&sortorder=asc")
  js <- jsonlite::fromJSON(url)
  stopifnot(isTRUE(js$header$success))
  tibble::as_tibble(js$result$records) |>
    dplyr::transmute(month = as.Date(paste0(end_of_month, "-01")),
                     rf_annual_pct = ir_1m, market = "HKEX") |>
    dplyr::filter(!is.na(rf_annual_pct))
}

#' Singapore: SingStat (via data.gov.sg) Singapore Overnight Rate Average
#' (SORA), monthly. SORA is MAS's benchmark short rate; there is no published
#' 1-month SGD bill series of comparable length.
get_rf_sg <- function() {
  url <- paste0("https://data.gov.sg/api/action/datastore_search?",
                "resource_id=d_5fe5a4bb4a1ecc4d8a56a095832e2b24&limit=50")
  js <- jsonlite::fromJSON(url)
  rec <- js$result$records
  row <- rec[rec$DataSeries == "Singapore Overnight Rate Average", ]
  stopifnot(nrow(row) == 1)
  vals <- unlist(row[, grepl("^\\d{4}[A-Z][a-z]{2}$", names(row))])
  tibble::tibble(key = names(vals), rf_annual_pct = suppressWarnings(as.numeric(vals))) |>
    dplyr::filter(!is.na(rf_annual_pct)) |>
    dplyr::transmute(month = as.Date(paste0("01", substr(key, 5, 7), substr(key, 1, 4)), "%d%b%Y"),
                     rf_annual_pct, market = "SGX") |>
    dplyr::arrange(month)
}

#' Convert annual % rates to monthly returns, lagged one month.
rf_monthly <- function(rates) {
  rates |>
    dplyr::group_by(market) |>
    dplyr::arrange(month, .by_group = TRUE) |>
    dplyr::mutate(rf = dplyr::lag(rf_annual_pct) / 100 / 12) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(rf)) |>
    dplyr::select(market, month, rf)
}
