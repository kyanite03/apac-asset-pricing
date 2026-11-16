# Checks hand-written matrix estimators against reference implementations
# and against simulated data where the true answer is known.

source(file.path("..", "..", "R", "models_linear.R"))

set.seed(2026)

test_that("ols_matrix matches lm()", {
  n <- 200
  x1 <- rnorm(n); x2 <- rnorm(n)
  y <- 0.5 + 1.2 * x1 - 0.7 * x2 + rnorm(n)
  fit <- ols_matrix(y, cbind(const = 1, x1, x2))
  ref <- lm(y ~ x1 + x2)
  expect_equal(unname(fit$coef), unname(coef(ref)), tolerance = 1e-10)
  expect_equal(unname(fit$vcov), unname(vcov(ref)), tolerance = 1e-10)
  expect_equal(unname(fit$resid), unname(resid(ref)), tolerance = 1e-10)
})

test_that("multivariate ols_matrix equals column-by-column lm()", {
  n <- 150
  f <- rnorm(n)
  Y <- sapply(1:5, function(j) 0.1 * j + j * 0.3 * f + rnorm(n))
  fit <- ols_matrix(Y, cbind(1, f))
  for (j in 1:5) expect_equal(unname(fit$coef[, j]), unname(coef(lm(Y[, j] ~ f))), tolerance = 1e-10)
})

test_that("hac_vcov matches sandwich::NeweyWest (no prewhitening, no adjustment)", {
  skip_if_not_installed("sandwich")
  n <- 300
  x <- as.numeric(arima.sim(list(ar = 0.6), n))
  e <- as.numeric(arima.sim(list(ar = 0.5), n))
  y <- 1 + 0.8 * x + e
  fit <- ols_matrix(y, cbind(1, x))
  for (L in c(0, 3, 6)) {
    ref <- sandwich::NeweyWest(lm(y ~ x), lag = L, prewhite = FALSE, adjust = FALSE)
    expect_equal(unname(hac_vcov(fit, L)), unname(ref), tolerance = 1e-10)
  }
})

test_that("linear_hypothesis matches car::linearHypothesis F-test", {
  skip_if_not_installed("car")
  n <- 120
  x1 <- rnorm(n); x2 <- rnorm(n)
  y <- 1 + 0.5 * x1 + 0.5 * x2 + rnorm(n)
  fit <- ols_matrix(y, cbind(1, x1, x2))
  C <- rbind(c(0, 1, -1), c(0, 1, 0))
  mine <- linear_hypothesis(fit, C, c(0, 0.5))
  ref <- car::linearHypothesis(lm(y ~ x1 + x2), c("x1 - x2 = 0", "x1 = 0.5"))
  expect_equal(unname(mine["F"]), ref$F[2], tolerance = 1e-8)
  expect_equal(unname(mine["p"]), ref$`Pr(>F)`[2], tolerance = 1e-8)
})

test_that("gls_matrix with identity weights equals OLS", {
  n <- 80
  x <- rnorm(n); y <- 2 - x + rnorm(n)
  X <- cbind(1, x)
  expect_equal(unname(gls_matrix(y, X, diag(n))$coef), unname(ols_matrix(y, X)$coef), tolerance = 1e-10)
})

# Simulate a market where a K-factor model holds (alphas zero) or fails.
sim_panel <- function(T_, N, K, alpha = 0) {
  F <- matrix(rnorm(T_ * K, 0.006, 0.045), T_, K)
  B <- matrix(runif(N * K, 0.5, 1.5), N, K)
  E <- matrix(rnorm(T_ * N, 0, 0.05), T_, N)
  Y <- matrix(alpha, T_, N, byrow = TRUE) + F %*% t(B) + E
  list(Y = Y, F = F, B = B)
}

test_that("grs_test equals the Cochrane MLE form of the statistic", {
  s <- sim_panel(120, 10, 2)
  g <- grs_test(s$Y, s$F)
  T_ <- 120; N <- 10; K <- 2
  X <- cbind(1, s$F)
  B <- solve(crossprod(X), crossprod(X, s$Y)); E <- s$Y - X %*% B
  Sig_mle <- crossprod(E) / T_
  mu <- colMeans(s$F); Om <- crossprod(sweep(s$F, 2, mu)) / T_
  a <- B[1, ]
  ref <- (T_ - N - K) / N * drop(t(a) %*% solve(Sig_mle) %*% a) /
    (1 + drop(t(mu) %*% solve(Om) %*% mu))
  expect_equal(g$stat, ref, tolerance = 1e-10)
})

test_that("grs_test has correct size under H0 and power under H1", {
  p0 <- replicate(400, { s <- sim_panel(120, 10, 1); grs_test(s$Y, s$F)$p })
  expect_lt(abs(mean(p0 < 0.05) - 0.05), 0.035)          # empirical size near 5%
  # Uniform p-values under H0 (exact F distribution with normal errors)
  expect_gt(ks.test(p0, "punif")$p.value, 0.01)
  p1 <- replicate(200, { s <- sim_panel(120, 10, 1, alpha = 0.01); grs_test(s$Y, s$F)$p })
  expect_gt(mean(p1 < 0.05), 0.8)                         # 1%/month alphas are detected
})

test_that("fama_macbeth recovers a known risk premium", {
  # Cross-section where E[r_i] = lambda * beta_i exactly, many assets.
  T_ <- 600; N <- 50; lambda <- 0.008
  beta <- seq(0.4, 1.8, length.out = N)
  f <- rnorm(T_, lambda, 0.04)                             # traded factor: premium = mean
  Y <- outer(f, beta) + matrix(rnorm(T_ * N, 0, 0.04), T_, N)
  fm <- fama_macbeth(Y, matrix(f, dimnames = list(NULL, "mkt")))
  est <- fm$estimate[fm$term == "mkt"]
  se <- fm$se_shanken[fm$term == "mkt"]
  expect_lt(abs(est - mean(f)), 4 * se)
  expect_lt(abs(fm$estimate[fm$term == "gamma0"]), 4 * fm$se_shanken[fm$term == "gamma0"])
  # Shanken SEs are never smaller than plain FM SEs for the factor premium
  expect_true(all(fm$se_shanken >= fm$se_fm - 1e-12))
})

test_that("fama_macbeth slopes equal a pooled cross-sectional OLS each month", {
  s <- sim_panel(60, 12, 1)
  fm <- fama_macbeth(s$Y, s$F)
  G <- attr(fm, "gammas"); b <- attr(fm, "betas")
  t5 <- coef(lm(s$Y[5, ] ~ b[, 1]))
  expect_equal(unname(G[5, ]), unname(t5), tolerance = 1e-10)
})

test_that("nw_mean_vcov matches sandwich::NeweyWest on an intercept-only regression", {
  skip_if_not_installed("sandwich")
  set.seed(11)
  g <- as.numeric(arima.sim(list(ar = 0.4), n = 300))
  for (L in c(0, 4, 12)) {
    ref <- sandwich::NeweyWest(lm(g ~ 1), lag = L, prewhite = FALSE, adjust = FALSE)
    expect_equal(drop(nw_mean_vcov(matrix(g), L)), drop(ref), tolerance = 1e-10)
  }
})

test_that("fama_macbeth Newey-West errors at lag 0 equal plain FM up to the T/(T-1) factor", {
  s <- sim_panel(120, 15, 2)
  fm <- fama_macbeth(s$Y, s$F, nw_lag = 0)
  expect_equal(fm$se_nw^2 * 120 / 119, fm$se_fm^2, tolerance = 1e-10)
})
