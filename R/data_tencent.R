# Tencent financial data: loader and integrity checks for the extracted CSV.
#
# data/processed/tencent_financials.csv is written by scripts/extract_tencent.py
# (one row per fiscal year, item and source report, with page number).

read_tencent <- function(path) {
  d <- readr::read_csv(path, show_col_types = FALSE,
                       col_types = readr::cols(fy = "c", item = "c", value = "d", source = "c", page = "i"))
  d$rank <- as.integer(stringr::str_extract(d$source, "\\d{4}"))
  d$summary <- grepl("summary", d$source)
  d
}

#' Latest-reported value of an item for a fiscal year ("2025", "2026H1", ...).
#' Statement figures are preferred; `restated = TRUE` uses the most recent
#' five-year summary instead (restated to the current presentation).
tval <- function(d, item, fy, restated = FALSE) {
  x <- d[d$item == item & d$fy == fy & d$summary == restated, ]
  if (!nrow(x)) stop("no value for ", item, " ", fy)
  x$value[which.max(x$rank)]
}

#' Integrity checks: accounting identities on the latest figures, and agreement
#' of the same figure across consecutive reports (excluding known restatements).
check_tencent <- function(d, years = as.character(2021:2025)) {
  g <- function(i, y) tryCatch(tval(d, i, y), error = function(e) NA_real_)
  ident <- purrr::map_dfr(years, function(y) tibble::tibble(
    fy = y,
    segments_sum = g("rev_vas", y) + g("rev_marketing", y) + g("rev_fintech_business", y) + g("rev_others", y) - g("revenue", y),
    gross_profit = g("revenue", y) + g("cost_of_revenues", y) - g("gross_profit", y),
    profit = g("profit_before_tax", y) + g("income_tax", y) - g("profit_for_year", y),
    net_cash = g("cash", y) + g("term_deposits_others", y) -
      (g("borrowings_noncurrent", y) + g("borrowings_current", y) + g("notes_noncurrent", y) + g("notes_current", y)) - g("net_cash", y)
  ))
  known_restated <- c("operating_profit", "other_gains", "nonifrs_operating_profit")
  dup <- d |>
    dplyr::group_by(fy, item) |>
    dplyr::summarise(n = dplyr::n(), spread = max(value) - min(value), .groups = "drop") |>
    dplyr::filter(n > 1)
  list(identities = ident,
       n_compared = nrow(dup),
       n_disagree = sum(dup$spread > 0.5 & !dup$item %in% known_restated),
       restated = dup |> dplyr::filter(spread > 0.5, item %in% known_restated))
}
