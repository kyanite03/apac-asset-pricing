# ============================================
# Fama-French APAC Replication — ASX Setup
# ============================================

# ---- 1. Libraries ----
library(tidyquant)
library(dplyr)
library(lubridate)
library(readr)
library(tidyverse)
library(quantmod)


# ---- 2. Parameters ----
start_date <- "2015-01-01"
end_date   <- "2024-12-31"

# Example ASX universe (expand later)
tickers <- c(
  "CBA.AX","BHP.AX","CSL.AX","NAB.AX","WBC.AX","ANZ.AX",
  "MQG.AX","WOW.AX","WES.AX","TLS.AX","RIO.AX",
  "GMG.AX","ALL.AX","QBE.AX","COL.AX","AMC.AX"
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

# ---- 10. Approximate Market Cap (using price only for now) ----
# NOTE: proper version uses shares outstanding (later)

market_cap <- prices %>%
  group_by(symbol, date) %>%
  summarise(price = last(adjusted), .groups = "drop")

# ---- 11. Assign Size Groups ----
size_groups <- market_cap %>%
  group_by(date) %>%
  mutate(
    size_group = ifelse(price <= median(price, na.rm = TRUE), "Small", "Big")
  ) %>%
  select(symbol, date, size_group)

returns_with_size <- returns %>%
  left_join(size_groups, by = c("symbol", "date"))

# ---- 12. SMB (Small Minus Big) ----
smb <- returns_with_size %>%
  group_by(date, size_group) %>%
  summarise(avg_ret = mean(ret, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = size_group, values_from = avg_ret) %>%
  mutate(SMB = Small - Big)

# ---- 13. CAPM + SMB ----
test_data <- returns_with_size %>%
  filter(symbol == "CBA.AX") %>%
  left_join(market_returns, by = "date") %>%
  left_join(smb, by = "date") %>%
  mutate(excess_ret = ret - Rf)

model_ff2 <- lm(excess_ret ~ Rm_excess + SMB, data = test_data)

summary(model_ff2)

# ============================================
# 14. Book-to-Market (BE/ME)
# ============================================
# ---- 14. Book-to-Market Proxy (v1) ----
fundamentals <- prices %>%
  group_by(symbol) %>%
  summarise(price = last(adjusted), .groups = "drop") %>%
  mutate(
    BE_ME = 1 / price   # proxy for value vs growth
  )

# ---- 15. Merge BE/ME into returns ----
returns_full <- returns_with_size %>%
  left_join(fundamentals, by = "symbol")

# ---- 16. Assign BM groups (Low/Mid/High) ----
returns_full <- returns_full %>%
  group_by(date) %>%
  mutate(
    bm_group = case_when(
      BE_ME <= quantile(BE_ME, 0.3, na.rm = TRUE) ~ "Low",
      BE_ME <= quantile(BE_ME, 0.7, na.rm = TRUE) ~ "Mid",
      TRUE ~ "High"
    )
  ) %>%
  ungroup()

table(returns_full$bm_group)

head(returns_full)

# NOTE:
# Due to limited availability of fundamental data for ASX equities via free APIs,
# book-to-market ratios are approximated using inverse price as a proxy.
# This preserves cross-sectional ranking but is not a true accounting measure.
#
# Future improvement:
# Replace with Compustat / WRDS data for accurate BE/ME construction.