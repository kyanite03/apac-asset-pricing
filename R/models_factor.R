# Statistical factor models: principal components of returns.
#
# Checked against prcomp() and against simulated returns with a known number
# of factors in tests/testthat/test-models_factor.R.

#' Principal components of a T x N return matrix.
#'
#' @param Y T x N matrix of (excess) returns.
#' @param scale TRUE = correlation-matrix PCA (each stock standardised), the
#'   default, so volatile stocks do not dominate.
#' @return list: values (eigenvalues), vectors (N x N loadings, columns = PCs,
#'   sign fixed so loadings sum to a positive number), scores (T x N factor
#'   series), share (variance explained), center, scale.
pca_returns <- function(Y, scale = TRUE) {
  Y <- as.matrix(Y)
  mu <- colMeans(Y)
  s <- if (scale) apply(Y, 2, stats::sd) else rep(1, ncol(Y))
  Z <- sweep(sweep(Y, 2, mu), 2, s, "/")
  C <- crossprod(Z) / (nrow(Z) - 1)
  e <- eigen(C, symmetric = TRUE)
  V <- e$vectors
  flip <- sign(colSums(V)); flip[flip == 0] <- 1
  V <- sweep(V, 2, flip, "*")
  dimnames(V) <- list(colnames(Y), paste0("PC", seq_len(ncol(V))))
  scores <- Z %*% V
  list(values = e$values, vectors = V, scores = scores,
       share = e$values / sum(e$values), center = mu, scale = s)
}

#' Marchenko-Pastur upper edge for the eigenvalues of a sample correlation
#' matrix of T independent observations on N uncorrelated variables.
#' Eigenvalues above it are unlikely to be pure noise.
mp_upper <- function(N, T_) (1 + sqrt(N / T_))^2

#' Parallel analysis: eigenvalues of correlation matrices after independently
#' permuting each column in time (destroys cross-correlation, keeps each
#' stock's distribution). Returns the chosen quantile of each ordered
#' eigenvalue across `reps` permutations.
parallel_analysis <- function(Y, reps = 200, prob = 0.95, seed = 1) {
  set.seed(seed)
  Y <- as.matrix(Y)
  ev <- replicate(reps, {
    P <- apply(Y, 2, sample)
    eigen(stats::cor(P), symmetric = TRUE, only.values = TRUE)$values
  })
  apply(ev, 1, stats::quantile, probs = prob)
}

#' Eigenportfolio returns: traded portfolios whose weights are proportional to
#' the PC loadings divided by each stock's volatility (so they are tradeable
#' versions of correlation-PCA factors), normalised to unit gross exposure.
#' Weights are estimated on one sample and can be applied to another.
eigenportfolio_weights <- function(pca, k) {
  W <- pca$vectors[, seq_len(k), drop = FALSE] / pca$scale
  sweep(W, 2, colSums(abs(W)), "/")
}
