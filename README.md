# APAC Asset Pricing Models

## Overview

This repository contains a collection of empirical finance projects replicating and extending classical asset pricing models using Asia-Pacific (APAC) market data.

The goal is to evaluate whether canonical models developed in US markets — such as CAPM and the Fama-French factor models — hold in APAC markets with different institutional structures, investor compositions, and macroeconomic dynamics.

---

## Motivation

Most empirical asset pricing research is based on US data. However, APAC markets (e.g. Australia, Hong Kong, China, Singapore) differ significantly in:

* Market structure (retail vs institutional dominance)
* Capital controls (especially China A-shares)
* Currency regimes (e.g. HKD peg, AUD commodity exposure)
* Regulatory environments

This project investigates whether standard risk factors explain returns in these markets.

---

## Planned Projects

### 1. Fama-French Three-Factor Model (APAC Replication)

* Replicate  using APAC equity markets
* Construct:

  * Market factor (R_m - R_f)
  * SMB (Small Minus Big)
  * HML (High Minus Low)
* Methodology:

  * Sort stocks into size and book-to-market portfolios
  * Construct 2×3 portfolios
  * Run time-series regressions
* Markets:

  * ASX (Australia)
  * HKEX (Hong Kong)
  * SGX (Singapore)
  * Shanghai/Shenzhen A-shares
* Key Question:

  * Do size and value premiums persist in APAC?

---

### 2. CAPM and Black-CAPM Testing

* Test standard CAPM:

  * ( R_i - R_f = \alpha + \beta (R_m - R_f) + \epsilon )
* Evaluate:

  * Significance of alpha
  * Model fit (R²)
* Extend to Black-CAPM (zero-beta version)
* Compare across APAC markets

---

### 3. Arbitrage Pricing Theory (APT)

* Test multi-factor models with varying factors:

  * Market
  * Macro factors (e.g. interest rates, exchange rates, commodities)
* Compare explanatory power vs Fama-French

---

### 4. Stochastic Modelling of Returns

* Compare distributional assumptions:

  * Geometric Brownian Motion
  * GARCH models
  * Regime-switching models
* Evaluate:

  * Volatility clustering
  * Fat tails
* Markets: major APAC indices

---

## Data Sources (Planned)

* Yahoo Finance (via R: quantmod / tidyquant)
* WRDS / Compustat (if accessible)
* Exchange data (ASX, HKEX, SSE)
* Potential APIs:

  * Tushare (China)
  * Akshare

---

## Tools & Methods

* R (primary language)
* Linear modelling (OLS, Fama-MacBeth)
* Time-series econometrics
* Portfolio construction techniques
* Statistical hypothesis testing

---

## Repository Structure

* `/data/` — raw and processed datasets
* `/scripts/` — data cleaning and model code
* `/reports/` — final outputs (Quarto/HTML)
* `/docs/` — GitHub Pages site (future)

---

## Next Steps

* [ ] Implement ASX Fama-French pipeline
* [ ] Construct SMB and HML factors
* [ ] Run time-series regressions
* [ ] Validate results against literature
* [ ] Extend to additional APAC markets

---

## Author

Kai Marsh
University of Melbourne — Student in BCom (Finance & Statistics)
