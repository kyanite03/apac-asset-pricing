source(file.path("..", "..", "R", "valuation_dcf.R"))

test_that("a stream growing at g forever equals the closed-form mid-year perpetuity", {
  r <- 0.08; g <- 0.03; F1 <- 100; n <- 10
  fcf <- F1 * (1 + g)^(0:(n - 1))
  t <- (1:n) - 0.5                                    # mid-year flows
  pv <- pv_stream(fcf, t, r, g, t_tv = n)
  closed <- F1 / (r - g) * (1 + r)^0.5               # perpetuity of mid-year flows
  expect_equal(pv$ev, closed, tolerance = 1e-10)
})

test_that("explicit horizon length does not change value when growth is constant", {
  r <- 0.07; g <- 0.02
  v <- sapply(c(5, 10, 20), function(n) {
    fcf <- 50 * (1 + g)^(0:(n - 1)); pv_stream(fcf, (1:n) - 0.5, r, g, t_tv = n)$ev
  })
  expect_equal(v, rep(v[1], 3), tolerance = 1e-10)
})

test_that("wacc_calc reduces to the cost of equity with no debt", {
  w <- wacc_calc(beta = 1.2, rf = 0.02, erp = 0.05, kd = 0.04, tax = 0.2, equity_value = 100, debt_value = 0)
  expect_equal(w$wacc, 0.02 + 1.2 * 0.05)
})

test_that("fade hits its endpoints and stays flat", {
  f <- fade(0.10, 0.02, n = 10, k_end = 5)
  expect_equal(f[1], 0.10); expect_equal(f[5], 0.02); expect_equal(f[10], 0.02)
  expect_true(all(diff(f[1:5]) < 0))
})

test_that("sotp bridge adds up", {
  bs <- list(cash = 10, term_deposits = 20, borrowings = 15, notes = 5, listed_bn = 0.1, unlisted_bn = 0.05, nci = 3)
  b <- sotp_bridge(ev_ops = 100, bs, holding_discount = 0.2, fx_cny_hkd = 1.1, shares_m = 10)
  expect_equal(b$equity_rmb_m, 100 + 30 - 20 + 80 + 40 - 3)
  expect_equal(b$per_share_hkd, b$equity_rmb_m / 10 * 1.1)
})
