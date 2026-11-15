# Build the shared monthly dataset used by all modules.
#
#   Rscript scripts/build_data.R        (run from the repo root)
#
# Writes to data/processed/:
#   universe.csv        ticker, name, market, sector
#   returns_monthly.csv symbol, month, ret          (simple total returns, local currency)
#   market_monthly.csv  market, month, mkt          (total-return index ETF per market)
#   rf_monthly.csv      market, month, rf           (monthly risk-free return, lagged one month)
#   rf_rates_raw.csv    market, month, rf_annual_pct (the published rates, for reference)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr)
})
source("R/data_prices.R")
source("R/data_rates.R")

from <- "2011-02-01"   # first month with a lagged rate available in all three markets
to   <- "2026-09-30"   # last month with all three risk-free series published

# ---- Universe: large, long-listed stocks in each market ---------------------
# Chosen as today's large caps with listings covering the sample, across
# sectors, including the names later modules need (banks for 07, energy for 08).
# This is survivor-selected (e.g. Hang Seng Bank, 0011.HK, was taken private by
# HSBC in 2025-26 and has no Yahoo history); see Limitations in each module.
# Thai Beverage (Y92.SI) is excluded: its Yahoo adjusted closes jump 60-210% in
# most dividend months (THB dividends on an SGD listing are mis-adjusted).
universe <- tribble(
  ~ticker,   ~name,                              ~market, ~sector,
  "CBA.AX",  "Commonwealth Bank",                "ASX",  "Banks",
  "NAB.AX",  "National Australia Bank",          "ASX",  "Banks",
  "WBC.AX",  "Westpac",                          "ASX",  "Banks",
  "ANZ.AX",  "ANZ",                              "ASX",  "Banks",
  "MQG.AX",  "Macquarie Group",                  "ASX",  "Financials (other)",
  "QBE.AX",  "QBE Insurance",                    "ASX",  "Financials (other)",
  "BHP.AX",  "BHP",                              "ASX",  "Materials",
  "RIO.AX",  "Rio Tinto",                        "ASX",  "Materials",
  "FMG.AX",  "Fortescue",                        "ASX",  "Materials",
  "AMC.AX",  "Amcor",                            "ASX",  "Materials",
  "WDS.AX",  "Woodside Energy",                  "ASX",  "Energy",
  "STO.AX",  "Santos",                           "ASX",  "Energy",
  "CSL.AX",  "CSL",                              "ASX",  "Health care",
  "WOW.AX",  "Woolworths",                       "ASX",  "Consumer",
  "WES.AX",  "Wesfarmers",                       "ASX",  "Consumer",
  "ALL.AX",  "Aristocrat Leisure",               "ASX",  "Consumer",
  "TLS.AX",  "Telstra",                          "ASX",  "Telecoms & utilities",
  "TCL.AX",  "Transurban",                       "ASX",  "Industrials",
  "GMG.AX",  "Goodman Group",                    "ASX",  "Real estate",
  "0005.HK", "HSBC Holdings",                    "HKEX", "Banks",
  "0939.HK", "China Construction Bank",          "HKEX", "Banks",
  "1398.HK", "ICBC",                             "HKEX", "Banks",
  "3988.HK", "Bank of China",                    "HKEX", "Banks",
  "1299.HK", "AIA Group",                        "HKEX", "Financials (other)",
  "2318.HK", "Ping An Insurance",                "HKEX", "Financials (other)",
  "0388.HK", "Hong Kong Exchanges & Clearing",   "HKEX", "Financials (other)",
  "0883.HK", "CNOOC",                            "HKEX", "Energy",
  "0857.HK", "PetroChina",                       "HKEX", "Energy",
  "0386.HK", "Sinopec",                          "HKEX", "Energy",
  "0700.HK", "Tencent",                          "HKEX", "Technology",
  "0941.HK", "China Mobile",                     "HKEX", "Telecoms & utilities",
  "0002.HK", "CLP Holdings",                     "HKEX", "Telecoms & utilities",
  "0003.HK", "Hong Kong & China Gas",            "HKEX", "Telecoms & utilities",
  "0016.HK", "Sun Hung Kai Properties",          "HKEX", "Real estate",
  "0012.HK", "Henderson Land",                   "HKEX", "Real estate",
  "0066.HK", "MTR Corporation",                  "HKEX", "Industrials",
  "0027.HK", "Galaxy Entertainment",             "HKEX", "Consumer",
  "D05.SI",  "DBS Group",                        "SGX",  "Banks",
  "O39.SI",  "OCBC",                             "SGX",  "Banks",
  "U11.SI",  "UOB",                              "SGX",  "Banks",
  "S68.SI",  "Singapore Exchange",               "SGX",  "Financials (other)",
  "Z74.SI",  "Singtel",                          "SGX",  "Telecoms & utilities",
  "U96.SI",  "Sembcorp Industries",              "SGX",  "Telecoms & utilities",
  "C6L.SI",  "Singapore Airlines",               "SGX",  "Industrials",
  "BN4.SI",  "Keppel",                           "SGX",  "Industrials",
  "C07.SI",  "Jardine Cycle & Carriage",         "SGX",  "Industrials",
  "F34.SI",  "Wilmar International",             "SGX",  "Consumer",
  "G13.SI",  "Genting Singapore",                "SGX",  "Consumer",
  "V03.SI",  "Venture Corporation",              "SGX",  "Technology",
  "C38U.SI", "CapitaLand Integrated Comm. Trust","SGX",  "Real estate",
  "A17U.SI", "CapitaLand Ascendas REIT",         "SGX",  "Real estate"
)

# Market proxies: index-tracking ETFs, whose adjusted closes include
# reinvested distributions (Yahoo's ^AXJO/^HSI/^STI are price-only indices).
market_etf <- c(ASX = "STW.AX",   # SPDR S&P/ASX 200
                HKEX = "2800.HK", # Tracker Fund of Hong Kong (Hang Seng Index)
                SGX = "ES3.SI")   # SPDR Straits Times Index ETF

# ---- Download ----------------------------------------------------------------
ret <- get_monthly_returns(universe$ticker, from, to)
mkt <- get_monthly_returns(unname(market_etf), from, to) |>
  mutate(market = names(market_etf)[match(symbol, market_etf)]) |>
  transmute(market, month, mkt = ret)

rates <- bind_rows(get_rf_au(), get_rf_hk(), get_rf_sg())
rf <- rf_monthly(rates) |> filter(month >= as.Date(from), month <= as.Date(to))

# ---- Checks --------------------------------------------------------------------
months <- seq(as.Date(from), lubridate::floor_date(as.Date(to), "month"), by = "month")
cover <- ret |> count(symbol, name = "n_months") |>
  right_join(universe, by = c("symbol" = "ticker")) |>
  mutate(n_months = coalesce(n_months, 0L))
message("Sample months: ", length(months))
message("Stocks with incomplete history:")
print(cover |> filter(n_months < length(months)) |> select(symbol, name, n_months))
stopifnot(all(table(mkt$market) == length(months)),
          all(table(rf$market) == length(months)))

# Flag implausible monthly moves (data errors usually show as |ret| > 100%)
big <- ret |> filter(abs(ret) > 0.6)
if (nrow(big)) { message("Large monthly returns to review:"); print(big) }

# ---- Write -------------------------------------------------------------------
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
write_csv(universe, "data/processed/universe.csv")
write_csv(ret |> arrange(symbol, month), "data/processed/returns_monthly.csv")
write_csv(mkt |> arrange(market, month), "data/processed/market_monthly.csv")
write_csv(rf |> arrange(market, month), "data/processed/rf_monthly.csv")
write_csv(rates |> filter(month >= as.Date(from) - 31, month <= as.Date(to)) |> arrange(market, month),
          "data/processed/rf_rates_raw.csv")
message("Done.")
