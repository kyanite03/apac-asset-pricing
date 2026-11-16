# Linear-model estimators written in matrix form.
#
# Every estimator here is checked against a reference implementation
# (lm(), sandwich::NeweyWest) and against simulated data in tests/.
#
#   OLS:  beta_hat = (X'X)^{-1} X'y,   Var(beta_hat) = s^2 (X'X)^{-1}
#   HAC:  Var(beta_hat) = (X'X)^{-1} S (X'X)^{-1},  S = Newey-West long-run covariance
#   GLS:  beta_hat = (X' W^{-1} X)^{-1} X' W^{-1} y

#' OLS by the normal equations.
#'
#' @param y numeric vector (n) or matrix (n x m) of responses. A matrix fits
#'   m regressions with the same X in one solve (multivariate regression).
#' @param X design matrix (n x k), including a column of ones if wanted.
#' @return list with coef (k x m), resid, fitted, sigma2, vcov (classical;
#'   only for a vector y), df, XtX_inv.
ols_matrix <- function(y, X) {
  X <- as.matrix(X)
  y_mat <- as.matrix(y)
  n <- nrow(X); k <- ncol(X)
  XtX_inv <- solve(crossprod(X))
  B <- XtX_inv %*% crossprod(X, y_mat)
  rownames(B) <- colnames(X)
  fitted <- X %*% B
  E <- y_mat - fitted
  df <- n - k
  sigma2 <- colSums(E^2) / df
  out <- list(coef = B, resid = E, fitted = fitted, sigma2 = sigma2,
              df = df, XtX_inv = XtX_inv, X = X, n = n, k = k)
  if (ncol(y_mat) == 1) {
    out$coef <- drop(B); names(out$coef) <- colnames(X)
    out$resid <- drop(E); out$fitted <- drop(fitted)
    out$vcov <- sigma2 * XtX_inv
  }
  out
}

#' Newey-West (Bartlett kernel) HAC covariance of OLS coefficients.
#'
#' Matches sandwich::NeweyWest(fit, lag = L, prewhite = FALSE, adjust = FALSE).
#' @param fit result of ols_matrix() with a vector response.
#' @param lag truncation lag L.
hac_vcov <- function(fit, lag) {
  X <- fit$X; e <- fit$resid; n <- fit$n
  u <- X * e                                   # n x k score contributions
  S <- crossprod(u)
  if (lag > 0) for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    G <- crossprod(u[(l + 1):n, , drop = FALSE], u[1:(n - l), , drop = FALSE])
    S <- S + w * (G + t(G))
  }
  fit$XtX_inv %*% S %*% fit$XtX_inv
}

#' Coefficient table (estimate, se, t, p) from a fit and a covariance matrix.
coef_table <- function(fit, V = fit$vcov) {
  est <- fit$coef
  se <- sqrt(diag(V))
  t <- est / se
  data.frame(term = names(est), estimate = est, se = se, t = t,
             p = 2 * pt(abs(t), fit$df, lower.tail = FALSE), row.names = NULL)
}

#' Feasible GLS with a known (or estimated) error covariance W (n x n).
gls_matrix <- function(y, X, W) {
  X <- as.matrix(X)
  W_inv <- solve(W)
  A <- solve(t(X) %*% W_inv %*% X)
  b <- drop(A %*% t(X) %*% W_inv %*% y)
  names(b) <- colnames(X)
  list(coef = b, vcov = A, resid = drop(y - X %*% b))
}

#' General linear hypothesis H0: C beta = c0, Wald F-test.
linear_hypothesis <- function(fit, C, c0 = rep(0, nrow(C)), V = fit$vcov) {
  C <- rbind(C)
  d <- C %*% fit$coef - c0
  q <- nrow(C)
  F <- drop(t(d) %*% solve(C %*% V %*% t(C)) %*% d) / q
  c(F = F, df1 = q, df2 = fit$df, p = pf(F, q, fit$df, lower.tail = FALSE))
}

#' Gibbons-Ross-Shanken (1989) test that all time-series alphas are zero.
#'
#' Fits Y = 1 a' + F B' + E for N test assets on K traded factors, then
#'   GRS = (T/N) (T-N-K)/(T-K-1) * a' Sigma^{-1} a / (1 + mu' Omega^{-1} mu)
#' with Sigma the residual covariance (divisor T-K-1) and mu, Omega the factor
#' mean and MLE covariance. Under normal errors GRS ~ F(N, T-N-K).
#'
#' @param Y T x N matrix of test-asset excess returns.
#' @param F T x K matrix (or vector) of factor excess returns.
grs_test <- function(Y, F) {
  Y <- as.matrix(Y); F <- as.matrix(F)
  T_ <- nrow(Y); N <- ncol(Y); K <- ncol(F)
  stopifnot(T_ > N + K)
  fit <- ols_matrix(Y, cbind(1, F))
  alpha <- fit$coef[1, ]
  Sigma <- crossprod(fit$resid) / (T_ - K - 1)
  mu <- colMeans(F)
  Omega <- crossprod(sweep(F, 2, mu)) / T_
  quad_a <- drop(t(alpha) %*% solve(Sigma, alpha))
  quad_f <- drop(t(mu) %*% solve(Omega, mu))
  stat <- (T_ / N) * ((T_ - N - K) / (T_ - K - 1)) * quad_a / (1 + quad_f)
  list(stat = stat, df1 = N, df2 = T_ - N - K,
       p = pf(stat, N, T_ - N - K, lower.tail = FALSE),
       alpha = alpha, betas = fit$coef[-1, , drop = FALSE],
       resid_cov = Sigma, sharpe_factors = sqrt(quad_f),
       sharpe_tangency = sqrt(quad_a + quad_f))
}

#' Fama-MacBeth (1973) two-pass cross-sectional regressions.
#'
#' Pass 1: full-sample time-series betas of each asset on the factors.
#' Pass 2: each month, regress the cross-section of excess returns on the
#' betas; the risk premia are the time averages of the monthly slopes.
#' Reports plain FM standard errors and Shanken (1992) errors-in-variables
#' corrected ones. It also reports Newey-West errors on the monthly slopes
#' (`se_nw`, robust to serial correlation in the slopes), and the same with the
#' Shanken adjustment applied (`se_nw_shanken`).
#'
#' @param Y T x N excess returns; F T x K factor excess returns.
#' @param intercept include a cross-sectional intercept (zero-beta excess
#'   rate) in pass 2?
#' @param betas optional N x K matrix of pre-estimated betas (skips pass 1,
#'   and the Shanken correction is then not applied).
#' @param nw_lag Newey-West truncation lag for `se_nw`.
fama_macbeth <- function(Y, F, intercept = TRUE, betas = NULL, nw_lag = 4) {
  Y <- as.matrix(Y); F <- as.matrix(F)
  T_ <- nrow(Y); N <- ncol(Y); K <- ncol(F)
  shanken_ok <- is.null(betas)
  if (is.null(betas)) {
    betas <- t(ols_matrix(Y, cbind(1, F))$coef[-1, , drop = FALSE])   # N x K
  }
  Z <- if (intercept) cbind(1, betas) else betas
  colnames(Z) <- c(if (intercept) "gamma0", colnames(F) %||% paste0("f", seq_len(K)))
  P <- solve(crossprod(Z), t(Z))                                    # (k x N)
  G <- t(P %*% t(Y))                                                # T x k monthly slopes
  colnames(G) <- colnames(Z)
  lambda <- colMeans(G)
  V_fm <- crossprod(sweep(G, 2, lambda)) / (T_ * (T_ - 1))
  se_fm <- sqrt(diag(V_fm))
  V_nw <- nw_mean_vcov(G, nw_lag)
  out <- data.frame(term = colnames(Z), estimate = lambda, se_fm = se_fm,
                    t_fm = lambda / se_fm, se_nw = sqrt(diag(V_nw)), row.names = NULL)
  out$t_nw <- lambda / out$se_nw
  if (shanken_ok) {
    f_bar <- colMeans(F)
    Sigma_f <- crossprod(sweep(F, 2, f_bar)) / (T_ - 1)
    lam_f <- lambda[(intercept + 1):length(lambda)]
    c_sh <- drop(t(lam_f) %*% solve(Sigma_f, lam_f))
    add <- matrix(0, ncol(Z), ncol(Z))
    add[(intercept + 1):ncol(Z), (intercept + 1):ncol(Z)] <- Sigma_f / T_
    V_sh <- (1 + c_sh) * V_fm + add
    out$se_shanken <- sqrt(diag(V_sh))
    out$t_shanken <- lambda / out$se_shanken
    out$se_nw_shanken <- sqrt(diag((1 + c_sh) * V_nw + add))
    out$t_nw_shanken <- lambda / out$se_nw_shanken
  }
  attr(out, "gammas") <- G
  attr(out, "betas") <- betas
  out
}

#' Newey-West (Bartlett) covariance of the column means of a T x k matrix.
#'
#' Equals hac_vcov() for a regression of each column on a constant, i.e.
#' sandwich::NeweyWest(lm(g ~ 1), lag = L, prewhite = FALSE, adjust = FALSE).
nw_mean_vcov <- function(G, lag) {
  G <- as.matrix(G); n <- nrow(G)
  u <- sweep(G, 2, colMeans(G))
  S <- crossprod(u)
  if (lag > 0) for (l in seq_len(lag)) {
    A <- crossprod(u[(l + 1):n, , drop = FALSE], u[1:(n - l), , drop = FALSE])
    S <- S + (1 - l / (lag + 1)) * (A + t(A))
  }
  S / n^2
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Seemingly unrelated regressions (Zellner, 1962) by feasible GLS.
#'
#' Equations m = 1..M share the same T observations. The system is stacked as
#' y = X b + e with Var(e) = Sigma (x) I_T, and estimated in two steps:
#' equation-by-equation OLS gives Sigma_hat (divisor T), then
#'   b_hat = (X' (Sigma^-1 (x) I) X)^-1 X' (Sigma^-1 (x) I) y.
#' When every equation has the same regressors, SUR equals OLS equation by
#' equation, but it still delivers the joint covariance needed for
#' cross-equation tests.
#'
#' @param ys list of M response vectors (length T each).
#' @param Xs list of M design matrices (T x k_m), named columns.
#' @return list: coef (named "eq:term"), vcov, Sigma, resid (T x M), df.
sur_fit <- function(ys, Xs) {
  M <- length(ys); T_ <- length(ys[[1]])
  eq <- names(ys) %||% paste0("eq", seq_len(M))
  E <- sapply(seq_len(M), function(m) ols_matrix(ys[[m]], Xs[[m]])$resid)
  Sigma <- crossprod(E) / T_
  dimnames(Sigma) <- list(eq, eq)
  X <- as.matrix(Matrix::bdiag(lapply(Xs, as.matrix)))
  colnames(X) <- unlist(lapply(seq_len(M), function(m) paste0(eq[m], ":", colnames(Xs[[m]]))))
  y <- unlist(ys)
  Om_inv <- kronecker(solve(Sigma), diag(T_))
  A <- solve(t(X) %*% Om_inv %*% X)
  b <- drop(A %*% t(X) %*% Om_inv %*% y)
  names(b) <- colnames(X)
  R <- matrix(y - X %*% b, T_, M, dimnames = list(NULL, eq))
  list(coef = b, vcov = A, Sigma = Sigma, resid = R, df = M * T_ - length(b), X = X)
}
