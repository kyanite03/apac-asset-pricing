# Price data: monthly total returns from Yahoo Finance adjusted closes.
#
# Yahoo caveats (stated in every write-up): survivorship (delisted firms are
# missing), occasional adjusted-close quirks around corporate actions, gaps.

#' Monthly simple total returns from month-end adjusted closes.
#'
#' Daily adjusted prices are pulled with tidyquant, the last trading day of
#' each calendar month is kept, and returns are computed month-end to
#' month-end. Dates are set to the first of the month (a month label), so
#' series from different exchanges line up regardless of holidays.
#'
#' @param tickers Yahoo symbols (e.g. "CBA.AX", "0700.HK", "D05.SI").
#' @param from,to date strings. The first month's return needs the prior
#'   month-end, so data are requested from one month before `from`.
get_monthly_returns <- function(tickers, from, to) {
  start <- as.Date(from) - 40
  px <- tidyquant::tq_get(tickers, from = start, to = as.Date(to) + 1)
  stopifnot(nrow(px) > 0)
  px |>
    dplyr::filter(!is.na(adjusted)) |>
    dplyr::mutate(month = lubridate::floor_date(date, "month")) |>
    dplyr::group_by(symbol, month) |>
    dplyr::slice_max(date, n = 1, with_ties = FALSE) |>
    dplyr::group_by(symbol) |>
    dplyr::arrange(month, .by_group = TRUE) |>
    dplyr::mutate(ret = adjusted / dplyr::lag(adjusted) - 1,
                  gap = as.numeric(month - dplyr::lag(month))) |>
    dplyr::ungroup() |>
    # a return is only valid if the previous observation is the previous month
    dplyr::filter(!is.na(ret), gap <= 31,
                  month >= lubridate::floor_date(as.Date(from), "month"),
                  month <= lubridate::floor_date(as.Date(to), "month")) |>
    dplyr::select(symbol, month, ret)
}
