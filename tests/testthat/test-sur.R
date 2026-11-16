source(file.path("..", "..", "R", "models_linear.R"))
set.seed(11)

sim_system <- function(T_ = 150, same_X = FALSE) {
  f <- rnorm(T_); z <- rnorm(T_)
  S <- matrix(c(1, .6, .4, .6, 1, .5, .4, .5, 1), 3) * 0.04
  E <- matrix(rnorm(T_ * 3), T_, 3) %*% chol(S)
  X1 <- cbind(const = 1, f = f)
  X2 <- if (same_X) X1 else cbind(const = 1, f = f, z = z)
  X3 <- X1
  list(ys = list(a = 0.1 + 0.8 * f + E[, 1], b = -0.1 + 1.2 * f + 0.3 * X2[, ncol(X2)] * (!same_X) + E[, 2],
                 c = 0.9 * f + E[, 3]),
       Xs = list(a = X1, b = X2, c = X3))
}

test_that("SUR equals equation-by-equation OLS when regressors are identical", {
  s <- sim_system(same_X = TRUE)
  fit <- sur_fit(s$ys, s$Xs)
  for (m in names(s$ys)) {
    ols <- coef(lm(s$ys[[m]] ~ s$Xs[[m]][, -1]))
    expect_equal(unname(fit$coef[grep(paste0("^", m, ":"), names(fit$coef))]), unname(ols), tolerance = 1e-10)
  }
})

test_that("SUR matches systemfit (two-step FGLS, Sigma divisor T)", {
  skip_if_not_installed("systemfit")
  s <- sim_system(same_X = FALSE)
  fit <- sur_fit(s$ys, s$Xs)
  d <- data.frame(ya = s$ys$a, yb = s$ys$b, yc = s$ys$c, f = s$Xs$a[, "f"], z = s$Xs$b[, "z"])
  ref <- systemfit::systemfit(list(a = ya ~ f, b = yb ~ f + z, c = yc ~ f), method = "SUR", data = d,
                              methodResidCov = "noDfCor")
  expect_equal(unname(fit$coef), unname(coef(ref)), tolerance = 1e-8)
  expect_equal(unname(fit$vcov), unname(vcov(ref)), tolerance = 1e-8)
})

test_that("sur_hac_vcov's diagonal blocks equal each equation's own Newey-West covariance", {
  set.seed(5)
  T_ <- 200; x <- as.numeric(arima.sim(list(ar = 0.3), T_))
  e <- matrix(rnorm(T_ * 3), T_, 3) %*% chol(matrix(c(1, .5, .3, .5, 1, .4, .3, .4, 1), 3))
  X <- cbind(const = 1, x = x)
  ys <- list(a = 0.1 + 0.8 * x + e[, 1], b = 0.9 * x + e[, 2], c = -0.1 + 1.1 * x + e[, 3])
  Xs <- list(a = X, b = X, c = X)
  fit <- sur_fit(ys, Xs)
  V <- sur_hac_vcov(fit, Xs, lag = 4)
  for (m in seq_along(ys)) {
    ref <- sandwich::NeweyWest(lm(ys[[m]] ~ x), lag = 4, prewhite = FALSE, adjust = FALSE)
    ix <- (2 * m - 1):(2 * m)
    expect_equal(unname(V[ix, ix]), unname(ref), tolerance = 1e-8)
  }
  # Off-diagonal blocks pick up the cross-equation error correlation
  expect_gt(V["a:x", "b:x"], 0)
})
