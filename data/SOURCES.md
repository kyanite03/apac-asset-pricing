# Data sources and provenance

Raw inputs live in `data/raw/`, which is gitignored: most sources carry no
redistribution licence, so the files are kept local and only processed outputs
in `data/processed/` are committed. This file records where each raw file came
from so the analysis can be rebuilt.

## Kenneth R. French Data Library: Asia Pacific ex Japan factors (Module 03)

Monthly, USD, percent. No reuse licence stated (copyright Eugene F. Fama and
Kenneth R. French), so the files are not committed.

The live library was unreachable from the network used for this analysis
(connection reset, November 2026). The files were retrieved on 2026-11-15 from
Internet Archive snapshots of the original URLs:

| File | Snapshot | Data coverage | SHA-256 |
|---|---|---|---|
| [`Asia_Pacific_ex_Japan_3_Factors_CSV.zip`](https://web.archive.org/web/20260309094837/https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/Asia_Pacific_ex_Japan_3_Factors_CSV.zip) | 2026-03-09 | 1990-07 to 2026-01 | `ed8d89061faeb53951572845df3b0e0ed4d46ad0e16a855e121643c77bb1c170` |
| [`Asia_Pacific_ex_Japan_5_Factors_CSV.zip`](https://web.archive.org/web/20260227051922/https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/Asia_Pacific_ex_Japan_5_Factors_CSV.zip) | 2026-02-27 | 1990-07 to 2026-01 | `29c51413c6131575720fa56f144560fa7a8de21299896be5f3c70ec816262bce` |
| [`Asia_Pacific_ex_Japan_Mom_Factor_CSV.zip`](https://web.archive.org/web/20260201042325/https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/Asia_Pacific_ex_Japan_Mom_Factor_CSV.zip) | 2026-02-01 | 1990-11 to 2025-12 | `4286c2e4f20a09d14705cd83ca47797b56a8de95675627a622781b335752742b` |

Save them to `data/raw/french/`. The momentum file ends in December 2025, so
the Module 03 tests stop there. French rebuilds the full history each month,
so files downloaded from the live library later may differ slightly from these.

## Other raw inputs

| Folder | Source | How to obtain |
|---|---|---|
| `tencent/` | Tencent Holdings annual reports FY2022–FY2025 and 2026 interim report | <https://www.tencent.com/investors/financial-reports/>. Extracted figures, with page references, are in `data/processed/tencent_financials.csv` |
| `worldbank/` | World Bank Commodity Price Data (Pink Sheet), monthly, CC BY 4.0 | `CMO-Historical-Data-Monthly.xlsx` from the World Bank commodity markets page |
| `australia/` | Australian Petroleum Statistics, Department of Climate Change, Energy, the Environment and Water | `australian-petroleum-statistics.xlsx`, downloaded manually |
| `ema/` | Singapore Energy Market Authority, Singapore Energy Statistics | `SES_tidy.xlsx`, downloaded manually (reuse terms unconfirmed) |
| `singstat/` | SingStat Table Builder API | Fetched by `R/data_commodities.R` |

Prices, FX and interest rates (RBA, HKMA, data.gov.sg) are fetched by the
`R/data_*.R` scripts via `scripts/build_data.R`.
