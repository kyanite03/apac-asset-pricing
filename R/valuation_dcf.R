# Discounted cash flow valuation engine (used by Module 06).
#
# Annual forecast with mid-year discounting from a valuation date, Gordon
# terminal value, and a sum-of-the-parts bridge from enterprise value to
# value per share. tests/testthat/test-valuation_dcf.R checks the discounting
# against closed-form growing-perpetuity values.

#' Present value of a cash-flow stream plus a Gordon terminal value.
#'
#' @param fcf cash flows; @param t their timing in years from the valuation date
#' @param r discount rate; @param g terminal growth (< r)
#' @param t_tv timing of the terminal value (end of the last forecast year)
#' @param fcf_tv cash flow of the first post-forecast year (defaults to last fcf x (1+g))
pv_stream <- function(fcf, t, r, g, t_tv, fcf_tv = fcf[length(fcf)] * (1 + g)) {
  stopifnot(r > g)
  pv_explicit <- sum(fcf / (1 + r)^t)
  tv <- fcf_tv / (r - g)
  # The terminal flows are mid-year too: the first arrives half a year after t_tv,
  # so the perpetuity is valued at t_tv - 0.5 and discounted from there.
  pv_tv <- tv / (1 + r)^(t_tv - 0.5)
  list(pv_explicit = pv_explicit, pv_tv = pv_tv, ev = pv_explicit + pv_tv, tv = tv)
}

#' Cost of capital from CAPM inputs and market-value weights.
wacc_calc <- function(beta, rf, erp, kd, tax, equity_value, debt_value) {
  ke <- rf + beta * erp
  w_d <- debt_value / (debt_value + equity_value)
  list(ke = ke, kd_after_tax = kd * (1 - tax), w_d = w_d,
       wacc = (1 - w_d) * ke + w_d * kd * (1 - tax))
}

#' Linear path from `start` (first year) to `end` (year `k_end`), flat afterwards.
fade <- function(start, end, n, k_end) {
  k <- seq_len(n)
  ifelse(k >= k_end, end, start + (end - start) * (k - 1) / (k_end - 1))
}

#' Tencent operating DCF for one parameter set.
#'
#' Years are FY2026..FY(2025 + n). The valuation date is 30 June 2026, so only
#' the second half of FY2026's cash flow is counted (at t = 0.25), and FY2027+
#' flows are mid-year (t = 1, 2, ...).
#'
#' @param base list of data anchors: rev2025 (named segment vector), g2026
#'   (segment growth in FY2026), capex_hist (total capex FY2020..FY2025),
#'   capex2026 (total capex in FY2026), ebitda_margin0 (FY2026 margin)
#' @param p list of assumptions: growth_mult, g_terminal, ebitda_margin_target,
#'   capex_intensity_ss, tax, lease_pct, wacc, n (forecast years), k_norm (year
#'   by which margin and capex reach steady state)
tencent_dcf <- function(base, p) {
  n <- p$n; years <- 2025 + seq_len(n)
  segs <- names(base$rev2025)
  # Segment revenue: FY2026 growth from H1 2026; from FY2027 the (scaled) FY2026
  # rate fades linearly to terminal growth by the final year.
  rev <- sapply(segs, function(s) {
    g <- c(base$g2026[[s]], fade(p$growth_mult * base$g2026[[s]], p$g_terminal, n - 1, n - 1))
    base$rev2025[[s]] * cumprod(1 + g)
  })
  revenue <- rowSums(rev)
  margin <- fade(base$ebitda_margin0, p$ebitda_margin_target, n, p$k_norm)
  ebitda <- revenue * margin
  capex_pct <- fade(base$capex2026 / revenue[1], p$capex_intensity_ss, n, p$k_norm)
  capex <- revenue * capex_pct
  # D&A: five-year straight-line depreciation of total capex (history, then forecast)
  cap_all <- c(base$capex_hist, capex)                     # FY2020.. onward
  off <- length(base$capex_hist)
  da <- sapply(seq_len(n), function(i) mean(cap_all[(off + i - 5):(off + i - 1)]))
  ebit <- ebitda - da
  tax <- pmax(ebit, 0) * p$tax
  lease <- revenue * p$lease_pct
  fcf <- ebitda - tax - capex - lease                      # = EBIT(1-t) + D&A - capex - lease
  t <- c(0.25, seq_len(n - 1))                             # H2 FY2026 at 0.25, then mid-year
  w <- c(0.5, rep(1, n - 1))                               # only H2 of FY2026 is after the valuation date
  pv <- pv_stream(fcf * w, t, p$wacc, p$g_terminal, t_tv = n - 0.5)
  list(table = data.frame(year = years, revenue = revenue, ebitda_margin = margin, ebitda = ebitda,
                          da = da, ebit = ebit, tax = tax, capex = capex, lease = lease, fcf = fcf,
                          t = t, weight = w),
       pv = pv)
}

#' Sum-of-the-parts bridge from operating EV to value per share.
#' All amounts in RMB million except `investments_*` in RMB billion and shares in millions.
sotp_bridge <- function(ev_ops, bs, holding_discount, fx_cny_hkd, shares_m) {
  parts <- c(
    operations = ev_ops,
    cash_and_deposits = bs$cash + bs$term_deposits,
    debt = -(bs$borrowings + bs$notes),
    listed_investments = 1000 * bs$listed_bn * (1 - holding_discount),
    unlisted_investments = 1000 * bs$unlisted_bn * (1 - holding_discount),
    minority_interests = -bs$nci
  )
  equity <- sum(parts)
  list(parts = parts, equity_rmb_m = equity,
       per_share_rmb = equity / shares_m, per_share_hkd = equity / shares_m * fx_cny_hkd)
}
