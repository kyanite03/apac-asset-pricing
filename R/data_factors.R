# Factor data and FX.
#
# Kenneth French Data Library files carry no reuse licence (copyright Fama and
# French), so the raw ZIPs live in data/raw/french/ (gitignored) and are
# parsed at render time. See data/raw/french/SOURCE.txt for provenance.

#' Read the monthly block of a Kenneth French CSV-in-ZIP file.
#'
#' The files contain a text preamble, a monthly table, a blank line, then an
#' annual table. Values are percentages; -99.99 marks missing data.
#' @return tibble with month (first of month) and one numeric column per
#'   factor, as decimal returns.
read_french_zip <- function(path) {
  inner <- utils::unzip(path, list = TRUE)$Name[1]
  txt <- readLines(unz(path, inner), warn = FALSE)
  txt <- sub("\r$", "", txt)
  start <- grep("^\\s*,", txt)[1]                         # header row starts with a comma
  rows <- start + 1
  while (rows <= length(txt) && grepl("^\\s*\\d{6}\\s*,", txt[rows])) rows <- rows + 1
  block <- txt[start:(rows - 1)]
  df <- utils::read.csv(text = block, check.names = FALSE, strip.white = TRUE)
  names(df)[1] <- "month"
  names(df) <- trimws(names(df))
  df$month <- as.Date(paste0(df$month, "01"), "%Y%m%d")
  num <- names(df) != "month"
  df[num] <- lapply(df[num], function(x) { x[x <= -99.99] <- NA; x / 100 })
  tibble::as_tibble(df)
}

#' French Asia Pacific ex Japan factors (USD): Mkt-RF, SMB, HML, RMW, CMA, RF, WML.
get_french_apac <- function(dir = "data/raw/french") {
  f5 <- read_french_zip(file.path(dir, "Asia_Pacific_ex_Japan_5_Factors_CSV.zip"))
  f3 <- read_french_zip(file.path(dir, "Asia_Pacific_ex_Japan_3_Factors_CSV.zip"))
  mom <- read_french_zip(file.path(dir, "Asia_Pacific_ex_Japan_Mom_Factor_CSV.zip"))
  names(mom)[2] <- "WML"
  f3 <- dplyr::rename(f3, SMB3 = SMB)                     # FF3 SMB differs slightly from FF5 SMB
  f5 |>
    dplyr::rename(MKT = `Mkt-RF`) |>
    dplyr::inner_join(dplyr::select(f3, month, SMB3), by = "month") |>
    dplyr::inner_join(mom, by = "month")
}

#' Monthly FX returns: change in USD per unit of local currency, month-end.
#'
#' A local-currency return r converts to USD as (1 + r)(1 + fx) - 1.
get_fx_monthly <- function(from, to) {
  pairs <- c(ASX = "AUDUSD=X", HKEX = "HKDUSD=X", SGX = "SGDUSD=X")
  get_monthly_returns(unname(pairs), from, to) |>
    dplyr::mutate(market = names(pairs)[match(symbol, pairs)]) |>
    dplyr::transmute(market, month, fx = ret)
}
