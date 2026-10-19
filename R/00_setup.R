# =============================================================================
# 00_setup.R  -  shared configuration, packages, and helper functions
# SilentHeat: quantifying the humid-heat blind spot in India's heatwave rule
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
  library(patchwork)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

# All paths are relative to the project root (run_all.R sets the working dir)
PROJ <- Sys.getenv("SILENTHEAT_HOME", getwd())

path <- function(...) file.path(PROJ, ...)
set.seed(2026)

# ---- Study design ------------------------------------------------------------
START_DATE <- as.Date("1981-01-01")
END_DATE   <- as.Date("2025-12-31")

# IMD category decides which heatwave rule applies to the city
CITIES <- data.frame(
  city   = c("Delhi", "Lucknow", "Ahmedabad", "Nagpur", "Kolkata",
             "Bhubaneswar", "Vellore", "Chennai", "Mumbai", "Visakhapatnam"),
  lat    = c(28.61, 26.85, 23.03, 21.15, 22.57, 20.30, 12.92, 13.08, 19.08, 17.69),
  lon    = c(77.21, 80.95, 72.58, 79.09, 88.36, 85.82, 79.13, 80.27, 72.88, 83.22),
  imd_category = c(rep("Plains", 7), rep("Coastal", 3)),
  stringsAsFactors = FALSE
)

# Physiological humid-heat thresholds on daily-maximum wet-bulb temperature (°C)
TW_DANGER   <- 29   # dangerous humid heat (Raymond et al. 2020 exceedance bins)
TW_CRITICAL <- 31   # ~upper critical limit for humid air (Vecellio et al. 2022)

# ---- Palette (validated with the dataviz CVD checker) -----------------------
PAL <- list(
  dark  = list(bg = "#000000", ink = "#F2F2F2", muted = "#A8A8A8", grid = "#2A2A2A",
               blue = "#4A90E2", amber = "#CC7722", grey = "#6E6E6E"),
  light = list(bg = "#FFFFFF", ink = "#111111", muted = "#555555", grid = "#E6E6E6",
               blue = "#2A78D6", amber = "#C8691F", grey = "#9A9A9A")
)
cat_cols <- function(mode) c(Plains = PAL[[mode]]$blue, Coastal = PAL[[mode]]$amber)

systemfonts_safe <- function() tryCatch(system("fc-list : family", intern = TRUE),
                                        error = function(e) character())
FONT <- if (any(grepl("Poppins", systemfonts_safe()))) "Poppins" else "sans"

theme_sh <- function(mode = "light", base = 13) {
  p <- PAL[[mode]]
  theme_minimal(base_size = base, base_family = FONT) +
    theme(
      plot.background  = element_rect(fill = p$bg, colour = NA),
      panel.background = element_rect(fill = p$bg, colour = NA),
      panel.grid.major = element_line(colour = p$grid, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      text        = element_text(colour = p$ink),
      axis.text   = element_text(colour = p$muted),
      axis.title  = element_text(colour = p$muted),
      strip.text  = element_text(colour = p$ink, face = "plain", hjust = 0),
      legend.text = element_text(colour = p$ink),
      legend.title = element_blank(),
      legend.position = "top",
      legend.justification = "left",
      plot.title    = element_text(colour = p$ink, size = base + 3, face = "plain"),
      plot.subtitle = element_text(colour = p$muted, size = base - 1),
      plot.caption  = element_text(colour = p$muted, size = base - 4, hjust = 0),
      plot.title.position = "plot",
      plot.margin = margin(12, 16, 10, 12)
    )
}

# Build a figure for both media: dark for the deck, light for the report.
# `build` is a function(mode) returning a ggplot.
save_fig <- function(build, name, w = 10, h = 5.6, dpi = 220) {
  for (mode in c("dark", "light")) {
    sub <- if (mode == "dark") "deck" else "report"
    f <- path("outputs", "figures", sub, paste0(name, ".png"))
    g <- build(mode)
    # Deck figures are transparent so the slide background shows through;
    # report figures sit on white
    fill <- if (mode == "dark") "transparent" else PAL[[mode]]$bg
    clear <- theme(plot.background  = element_rect(fill = fill, colour = NA),
                   panel.background = element_rect(fill = fill, colour = NA),
                   legend.background = element_rect(fill = fill, colour = NA),
                   legend.key = element_rect(fill = fill, colour = NA))
    g <- if (inherits(g, "patchwork")) {
      (g & clear) + plot_annotation(theme = clear)   # patchwork's outer canvas
    } else g + clear
    ggsave(f, g, width = w, height = h, dpi = dpi, units = "in", bg = fill)
  }
  invisible(name)
}

save_table <- function(df, name) {
  write.csv(df, path("outputs", "tables", paste0(name, ".csv")), row.names = FALSE)
  invisible(df)
}

# ---- Thermodynamics ----------------------------------------------------------
# Wet-bulb temperature from air temperature (°C) and RH (%), Stull (2011)
stull_wetbulb <- function(t, rh) {
  t * atan(0.151977 * sqrt(rh + 8.313659)) + atan(t + rh) - atan(rh - 1.676331) +
    0.00391838 * rh^1.5 * atan(0.023101 * rh) - 4.686035
}

# US NWS heat index (Rothfusz regression + adjustments), the equation IMD's
# experimental Heat Index follows. Input/Output in °C.
heat_index <- function(t_c, rh) {
  t <- t_c * 9 / 5 + 32
  simple <- 0.5 * (t + 61 + (t - 68) * 1.2 + rh * 0.094)
  hi <- -42.379 + 2.04901523 * t + 10.14333127 * rh - 0.22475541 * t * rh -
    0.00683783 * t^2 - 0.05481717 * rh^2 + 0.00122874 * t^2 * rh +
    0.00085282 * t * rh^2 - 0.00000199 * t^2 * rh^2
  adj_dry <- ifelse(rh < 13 & t >= 80 & t <= 112,
                    -((13 - rh) / 4) * sqrt(pmax(0, (17 - abs(t - 95)) / 17)), 0)
  adj_wet <- ifelse(rh > 85 & t >= 80 & t <= 87, ((rh - 85) / 10) * ((87 - t) / 5), 0)
  hi <- hi + adj_dry + adj_wet
  out <- ifelse((simple + t) / 2 < 80, simple, hi)
  (out - 32) * 5 / 9
}

# IMD experimental Heat Index colour bands
hi_band <- function(hi) cut(hi, c(-Inf, 35, 45, 55, Inf),
                            labels = c("Green", "Yellow", "Orange", "Red"))

# ---- Run-length helpers ------------------------------------------------------
# For a logical vector, length of the run each element belongs to (0 if FALSE)
run_length_of <- function(x) {
  x[is.na(x)] <- FALSE
  r <- rle(x)
  rep(ifelse(r$values, r$lengths, 0L), r$lengths)
}
spell_lengths <- function(x) {
  x[is.na(x)] <- FALSE
  r <- rle(x)
  r$lengths[r$values]
}

# ---- Inference helpers written from first principles ------------------------
wilson_ci <- function(x, n, conf = 0.95) {
  z <- qnorm(1 - (1 - conf) / 2)
  p <- x / n
  centre <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  half   <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  data.frame(est = p, lo = centre - half, hi = centre + half)
}

cohens_kappa <- function(tab) {
  n  <- sum(tab)
  po <- sum(diag(tab)) / n
  pe <- sum(rowSums(tab) * colSums(tab)) / n^2
  (po - pe) / (1 - pe)
}

# Mann-Kendall trend test with tie correction + Sen's slope and its CI
mann_kendall <- function(x, conf = 0.95) {
  x <- x[!is.na(x)]
  n <- length(x)
  ij <- which(upper.tri(matrix(0, n, n)), arr.ind = TRUE)  # pairs i < j
  i <- ij[, 1]; j <- ij[, 2]
  S <- sum(sign(x[j] - x[i]))
  ties <- table(x); ties <- ties[ties > 1]
  varS <- (n * (n - 1) * (2 * n + 5) - sum(ties * (ties - 1) * (2 * ties + 5))) / 18
  Z <- if (S > 0) (S - 1) / sqrt(varS) else if (S < 0) (S + 1) / sqrt(varS) else 0
  slopes <- sort((x[j] - x[i]) / (j - i))
  N <- length(slopes)
  C <- qnorm(1 - (1 - conf) / 2) * sqrt(varS)
  lo <- slopes[max(1, floor((N - C) / 2))]
  hi <- slopes[min(N, ceiling((N + C) / 2) + 1)]
  data.frame(n = n, S = S, var_S = varS, Z = Z, p_value = 2 * pnorm(-abs(Z)),
             tau = S / (n * (n - 1) / 2), sen_slope = median(slopes),
             sen_lo = lo, sen_hi = hi)
}

# ---- Generalised Extreme Value distribution (Coles 2001 notation) ----------
pgev <- function(z, mu, sigma, xi) {
  if (abs(xi) < 1e-6) return(exp(-exp(-(z - mu) / sigma)))
  y <- pmax(1 + xi * (z - mu) / sigma, 0)
  exp(-y^(-1 / xi))
}
qgev <- function(p, mu, sigma, xi) {
  if (abs(xi) < 1e-6) return(mu - sigma * log(-log(p)))
  mu - sigma / xi * (1 - (-log(p))^(-xi))
}
rgev <- function(n, mu, sigma, xi) qgev(runif(n), mu, sigma, xi)

gev_nll <- function(par, z, t = NULL) {
  # par = (mu0, [mu1], log_sigma, xi); location linear in covariate t if given
  if (is.null(t)) { mu <- par[1]; sigma <- exp(par[2]); xi <- par[3] }
  else            { mu <- par[1] + par[2] * t; sigma <- exp(par[3]); xi <- par[4] }
  y <- 1 + xi * (z - mu) / sigma
  if (any(y <= 0) || sigma <= 0) return(1e10)
  if (abs(xi) < 1e-6) {
    s <- (z - mu) / sigma
    return(length(z) * log(sigma) + sum(s) + sum(exp(-s)))
  }
  length(z) * log(sigma) + (1 + 1 / xi) * sum(log(y)) + sum(y^(-1 / xi))
}

fit_gev <- function(z, t = NULL) {
  start <- c(mean(z) - 0.45 * sd(z), log(0.78 * sd(z)), -0.1)
  if (!is.null(t)) start <- c(start[1], 0, start[2:3])
  best <- NULL
  for (xi0 in c(-0.3, -0.1, 0.1)) {
    s <- start; s[length(s)] <- xi0
    f <- optim(s, gev_nll, z = z, t = t, method = "Nelder-Mead",
               control = list(maxit = 5000, reltol = 1e-12))
    f <- optim(f$par, gev_nll, z = z, t = t, method = "BFGS",
               control = list(maxit = 1000, reltol = 1e-12))
    if (is.null(best) || f$value < best$value) best <- f
  }
  p <- best$par
  # Report on the natural scale and get the observed information there
  nat <- p; nat[length(nat) - 1] <- exp(p[length(p) - 1])
  nll_nat <- function(q) { q2 <- q; q2[length(q2) - 1] <- log(q[length(q) - 1])
                           gev_nll(q2, z = z, t = t) }
  H <- optimHess(nat, nll_nat)
  V <- tryCatch(solve(H), error = function(e) MASS::ginv(H))
  nm <- if (is.null(t)) c("mu", "sigma", "xi") else c("mu0", "mu1", "sigma", "xi")
  names(nat) <- nm; dimnames(V) <- list(nm, nm)
  list(par = nat, vcov = V, se = sqrt(pmax(diag(V), 0)), loglik = -best$value,
       n = length(z), conv = best$convergence)
}

# Return level for return period T (years) and its delta-method standard error
gev_return_level <- function(fit, T, mu_override = NULL) {
  mu <- if (is.null(mu_override)) fit$par["mu"] else mu_override
  sigma <- fit$par["sigma"]; xi <- fit$par["xi"]
  yp <- -log(1 - 1 / T)
  z  <- mu - sigma / xi * (1 - yp^(-xi))
  grad <- c(1,
            -(1 - yp^(-xi)) / xi,
            sigma * (1 - yp^(-xi)) / xi^2 - sigma / xi * yp^(-xi) * log(yp))
  se <- sqrt(as.numeric(t(grad) %*% fit$vcov[c("mu", "sigma", "xi"),
                                              c("mu", "sigma", "xi")] %*% grad))
  data.frame(T = T, level = unname(z), se = se)
}

# ---- Two-state Markov chain --------------------------------------------------
markov_counts <- function(x, group) {
  # x: logical daily state; group: season id (transitions never cross groups)
  same <- c(FALSE, group[-1] == group[-length(group)])
  from <- x[c(NA, seq_along(x)[-length(x)])][same]
  to   <- x[same]
  tab <- table(factor(from, c(FALSE, TRUE)), factor(to, c(FALSE, TRUE)))
  dimnames(tab) <- list(from = c("calm", "danger"), to = c("calm", "danger"))
  tab
}

fmt_p <- function(p) ifelse(p < 0.001, "< 0.001", formatC(p, format = "f", digits = 3))
