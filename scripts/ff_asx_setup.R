# ============================================
# Fama-French APAC Replication — ASX Setup
# ============================================

# ---- 1. Libraries ----
library(tidyquant)
library(dplyr)
library(lubridate)
library(readr)

# ---- 2. Parameters ----
start_date <- "2015-01-01"
end_date   <- "2024-12-31"

# Example ASX universe (expand later)
tickers <- c(
  "CBA.AX", "BHP.AX", "WBC.AX",
  "NAB.AX", "ANZ.AX", "WOW.AX",
  "CSL.AX", "MQG.AX"
)

# ---- 3. Download Price Data ----
prices <- tq_get(
  tickers,
  from = start_date,
  to   = end_date
)

# ---- 4. Compute Monthly Returns ----
returns <- prices %>%
  group_by(symbol) %>%
  tq_transmute(
    select     = adjusted,
    mutate_fun = periodReturn,
    period     = "monthly",
    col_rename = "ret"
  ) %>%
  ungroup()

# ---- 5. Create Market Proxy (Equal-weight for now) ----
market_returns <- returns %>%
  group_by(date) %>%
  summarise(Rm = mean(ret, na.rm = TRUE))

# ---- 6. Risk-Free Rate (Proxy) ----
# Using constant approximation (replace later with real data)
rf <- 0.002  # ~0.2% monthly (~2.4% annual)

market_returns <- market_returns %>%
  mutate(
    Rf = rf,
    Rm_excess = Rm - Rf
  )

# ---- 7. Save Outputs ----
write_csv(returns, "data/asx_returns.csv")
write_csv(market_returns, "data/asx_market.csv")

# ---- 8. Quick Check ----
print(head(market_returns))

# ---- 9. Test CAPM on one stock ----
test_data <- returns %>%
  filter(symbol == "CBA.AX") %>%
  left_join(market_returns, by = "date") %>%
  mutate(excess_ret = ret - Rf)

model <- lm(excess_ret ~ Rm_excess, data = test_data)

summary(model)