# Build the monthly oil dataset for Module 08.
#
#   FRED_API_KEY=... Rscript scripts/build_oil_data.R      (run from the repo root)
#
# Sources (raw files in gitignored data/raw/; processed extracts committed):
#   FRED (St. Louis Fed, via fredr): Brent and WTI daily spot (EIA), aggregated to month-end and monthly average
#   World Bank Pink Sheet (CC BY 4.0): Dubai crude, Brent, WTI, iron ore monthly averages
#   Australian Petroleum Statistics, DCCEEW via data.gov.au (CC BY 3.0 AU): refining, imports by source, stocks, cover
#   Maritime and Port Authority of Singapore via data.gov.sg (Singapore Open Data Licence): bunker sales
#   Yahoo Finance: monthly total returns for energy names not in the core universe (Ampol, Viva Energy, Beach Energy)
#
# Writes data/processed/oil_monthly.csv, aus_fuel_imports_by_source.csv, oil_equities_extra_returns.csv

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(readr) })
source("R/data_prices.R")
source("R/data_commodities.R")

from <- "2010-01-01"; to <- "2026-09-30"

# ---- Prices ------------------------------------------------------------------
fred <- bind_rows(get_fred_monthly("DCOILBRENTEU", from), get_fred_monthly("DCOILWTICO", from)) |>
  filter(month <= as.Date(to)) |>
  mutate(series = recode(series_id, DCOILBRENTEU = "brent", DCOILWTICO = "wti")) |>
  select(month, series, price_end, price_avg) |>
  pivot_wider(names_from = series, values_from = c(price_end, price_avg), names_glue = "{series}_{.value}")
wb <- read_pinksheet("data/raw/worldbank/CMO-Historical-Data-Monthly.xlsx",
                     c("Crude oil, Brent", "Crude oil, Dubai", "Iron ore, cfr spot")) |>
  mutate(series = recode(series, "Crude oil, Brent" = "brent_wb_avg", "Crude oil, Dubai" = "dubai_wb_avg",
                         "Iron ore, cfr spot" = "ironore_wb_avg")) |>
  pivot_wider(names_from = series, values_from = price)

# ---- Australia: Australian Petroleum Statistics ------------------------------
aps_file <- "data/raw/australia/australian-petroleum-statistics.xlsx"
aps <- function(sheet) readxl::read_excel(aps_file, sheet = sheet) |>
  mutate(month = as.Date(lubridate::floor_date(as.Date(Month), "month")))
num <- function(x) suppressWarnings(as.numeric(x))
ref <- aps("Refinery production") |>
  transmute(month, aus_refinery_input_ml = num(`Total input (ML)`),
            aus_refinery_indigenous_pct = num(`Percentage indigenous: Total input (%)`))
imp <- aps("Imports volume") |>
  transmute(month, aus_crude_imports_ml = num(`Crude oil & other refinery feedstocks (ML)`),
            aus_product_imports_ml = num(`Total refined petroleum products (ML)`))
stk <- aps("Stock volume by product") |>
  transmute(month, aus_stocks_total_ml = num(`Total stocks COE (ML)`),
            aus_stocks_diesel_ml = num(`Diesel oil (ML)`), aus_stocks_gasoline_ml = num(`Automotive gasoline (ML)`),
            aus_stocks_jet_ml = num(`Aviation turbine fuel (ML)`))
cov <- aps("IEA days net import cover") |>
  transmute(month, aus_iea_days_cover = num(`IEA days of net import coverage`))
sales <- aps("Sales of products") |>
  transmute(month, aus_diesel_sales_ml = num(`Diesel oil: total (ML)`),
            aus_gasoline_sales_ml = num(`Automotive gasoline total (ML)`))

# Refined-product imports by source country (individual product columns only)
ibc <- readxl::read_excel(aps_file, sheet = "Imports volume by country")
prod_cols <- setdiff(names(ibc), c("Month", "Source country", "Crude oil & other refinery feedstocks (ML)",
                                   "Total refined petroleum products (ML)", "Total oil imports (ML)", "Natural gas (ML)"))
by_src <- ibc |>
  mutate(month = as.Date(lubridate::floor_date(as.Date(Month), "month")),
         products_ml = rowSums(across(all_of(prod_cols), num), na.rm = TRUE)) |>
  group_by(month, source = `Source country`) |> summarise(products_ml = sum(products_ml), .groups = "drop")
# Check: country rows sum to the national total of refined-product imports
chk <- by_src |> group_by(month) |> summarise(s = sum(products_ml)) |> inner_join(imp, by = "month") |>
  mutate(rel = abs(s - aus_product_imports_ml) / aus_product_imports_ml)
message("Imports by country vs national total: median relative gap ", signif(median(chk$rel, na.rm = TRUE), 3),
        ", max ", signif(max(chk$rel, na.rm = TRUE), 3))

# ---- Singapore: bunker sales (MPA) --------------------------------------------
js <- jsonlite::fromJSON(paste0("https://data.gov.sg/api/action/datastore_search?",
                                "resource_id=d_89d2874dad74a273270369334f1e7d28&limit=1000"))
bunker <- tibble::as_tibble(js$result$records) |>
  transmute(month = as.Date(paste0(month, "-01")), sg_bunker_sales_kt = num(bunker_sales))

# ---- Combine -------------------------------------------------------------------
oil <- fred |>
  full_join(wb, by = "month") |>
  left_join(ref, by = "month") |> left_join(imp, by = "month") |> left_join(stk, by = "month") |>
  left_join(cov, by = "month") |> left_join(sales, by = "month") |> left_join(bunker, by = "month") |>
  filter(month >= as.Date(from), month <= as.Date(to)) |>
  arrange(month)

# ---- Extra energy equities (not in the core 51-stock universe) -----------------
extra <- get_monthly_returns(c("ALD.AX", "VEA.AX", "BPT.AX"), "2011-02-01", to)

dir.create("data/processed", showWarnings = FALSE)
write_csv(oil, "data/processed/oil_monthly.csv")
write_csv(by_src |> filter(month >= as.Date(from)), "data/processed/aus_fuel_imports_by_source.csv")
write_csv(extra, "data/processed/oil_equities_extra_returns.csv")
message("oil_monthly: ", nrow(oil), " months, ", ncol(oil) - 1, " series; last month ", max(oil$month))
print(oil |> summarise(across(-month, ~ sum(!is.na(.x)))) |> pivot_longer(everything(), names_to = "series", values_to = "months"), n = 40)
