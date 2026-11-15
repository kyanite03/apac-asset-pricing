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
