source(file.path("..", "..", "R", "models_factor.R"))

set.seed(7)

test_that("pca_returns matches prcomp on the correlation matrix", {
  Y <- matrix(rnorm(200 * 8), 200, 8) %*% matrix(runif(64), 8, 8)
  p <- pca_returns(Y)
  ref <- prcomp(Y, center = TRUE, scale. = TRUE)
  expect_equal(p$values, ref$sdev^2, tolerance = 1e-10)
  # eigenvectors equal up to sign
  for (j in 1:8) expect_equal(abs(unname(p$vectors[, j])), abs(unname(ref$rotation[, j])), tolerance = 1e-8)
  expect_equal(sum(p$share), 1)
})

test_that("pure noise produces no eigenvalue far above the Marchenko-Pastur edge", {
  T_ <- 400; N <- 50
  ev <- eigen(cor(matrix(rnorm(T_ * N), T_, N)), only.values = TRUE)$values
  expect_lt(ev[1], mp_upper(N, T_) * 1.15)
})

test_that("a planted 3-factor structure gives exactly 3 eigenvalues above both noise benchmarks", {
  T_ <- 300; N <- 40; K <- 3
  F <- matrix(rnorm(T_ * K), T_, K)
  B <- matrix(rnorm(N * K, 0, 0.8), N, K)
  Y <- F %*% t(B) + matrix(rnorm(T_ * N), T_, N)
  p <- pca_returns(Y)
  expect_equal(sum(p$values > mp_upper(N, T_)), K)
  expect_equal(sum(p$values > parallel_analysis(Y, reps = 50)), K)
  # The first K PC scores span the true factors (canonical correlations near 1)
  cc <- cancor(p$scores[, 1:K], F)$cor
  expect_gt(min(cc), 0.95)
})

test_that("eigenportfolio weights have unit gross exposure", {
  Y <- matrix(rnorm(120 * 10), 120, 10)
  W <- eigenportfolio_weights(pca_returns(Y), 3)
  expect_equal(unname(colSums(abs(W))), rep(1, 3))
})
