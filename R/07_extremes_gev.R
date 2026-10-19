# =============================================================================
# 07_extremes_gev.R  -  RQ3: how extreme can humid heat get, and is the
# tail shifting?  Generalised Extreme Value (GEV) analysis of annual maxima.
#   * GEV likelihood + MLE written from scratch (optim), checked against evd::fgev
#   * Gumbel vs GEV likelihood-ratio test
#   * return levels with delta-method and parametric-bootstrap intervals
#   * non-stationary GEV (location trend) + LRT
# =============================================================================

set.seed(2026)   # reproducible bootstrap / permutation / Monte Carlo draws
annual <- readRDS(path("data", "processed", "annual.rds"))
B_BOOT <- 500
RP <- c(10, 25, 50, 100)

gev_city <- function(x) {
  z <- x$max_twmax; yr <- x$year; tdec <- (yr - 2000) / 10
  st <- fit_gev(z)                                     # stationary
  ns <- fit_gev(z, t = tdec)                           # mu(t) = mu0 + mu1 * t
  gum <- optim(c(mean(z) - 0.45 * sd(z), log(0.78 * sd(z))),
               function(p) gev_nll(c(p, 0), z), method = "BFGS")  # xi = 0
  ref <- evd::fgev(z, std.err = FALSE)                 # independent check

  rl <- do.call(rbind, lapply(RP, function(T) gev_return_level(st, T)))
  boot <- replicate(B_BOOT, {
    zb <- rgev(length(z), st$par["mu"], st$par["sigma"], st$par["xi"])
    fb <- tryCatch(fit_gev(zb), error = function(e) NULL)
    if (is.null(fb)) rep(NA, length(RP))
    else sapply(RP, function(T) qgev(1 - 1 / T, fb$par["mu"], fb$par["sigma"], fb$par["xi"]))
  })
  rl$delta_lo <- rl$level - 1.96 * rl$se
  rl$delta_hi <- rl$level + 1.96 * rl$se
  rl$boot_lo <- apply(boot, 1, quantile, 0.025, na.rm = TRUE)
  rl$boot_hi <- apply(boot, 1, quantile, 0.975, na.rm = TRUE)
  rl$city <- x$city[1]

  # Under the non-stationary model: today's chance of beating the level that
  # was a 1-in-50-year event in 1985
  mu85 <- ns$par["mu0"] + ns$par["mu1"] * (1985 - 2000) / 10
  mu25 <- ns$par["mu0"] + ns$par["mu1"] * (2025 - 2000) / 10
  z50_85 <- qgev(1 - 1 / 50, mu85, ns$par["sigma"], ns$par["xi"])
  p_now  <- 1 - pgev(z50_85, mu25, ns$par["sigma"], ns$par["xi"])

  # Probability of at least one critical (>= 31 °C) day in 2026-2035 under the
  # trend model, assuming independent years: 1 - prod(1 - p_t)
  fut <- (2026:2035 - 2000) / 10
  p_crit <- sapply(fut, function(t) 1 - pgev(TW_CRITICAL, ns$par["mu0"] + ns$par["mu1"] * t,
                                             ns$par["sigma"], ns$par["xi"]))
  p_crit_st <- 1 - pgev(TW_CRITICAL, st$par["mu"], st$par["sigma"], st$par["xi"])

  lrt_trend  <- 2 * (ns$loglik - st$loglik)
  lrt_gumbel <- 2 * (st$loglik - (-gum$value))
  list(
    params = data.frame(
      city = x$city[1], imd_category = x$imd_category[1], n_years = length(z),
      mu = st$par["mu"], mu_se = st$se["mu"], sigma = st$par["sigma"],
      sigma_se = st$se["sigma"], xi = st$par["xi"], xi_se = st$se["xi"],
      loglik = st$loglik,
      evd_mu = ref$estimate["loc"], evd_sigma = ref$estimate["scale"],
      evd_xi = ref$estimate["shape"],
      gumbel_LRT = lrt_gumbel, gumbel_p = pchisq(lrt_gumbel, 1, lower.tail = FALSE),
      ns_mu1_per_decade = ns$par["mu1"], ns_mu1_se = ns$se["mu1"],
      trend_LRT = lrt_trend, trend_p = pchisq(lrt_trend, 1, lower.tail = FALSE),
      z50_1985 = z50_85, return_period_now = 1 / p_now,
      p_critical_any_2026_35_trend = 1 - prod(1 - p_crit),
      p_critical_any_2026_35_stationary = 1 - (1 - p_crit_st)^10,
      max_observed = max(z), year_of_max = yr[which.max(z)]),
    rl = rl, st = st, ns = ns, z = z, years = yr)
}

res <- lapply(split(annual, annual$city), gev_city)
gev_params <- bind_rows(lapply(res, `[[`, "params")); rownames(gev_params) <- NULL
gev_rl     <- bind_rows(lapply(res, `[[`, "rl"));     rownames(gev_rl) <- NULL
save_table(gev_params, "gev_parameters")
save_table(gev_rl, "gev_return_levels")
saveRDS(res, path("outputs", "tables", "gev_fits.rds"))

# ---- Figure: return-level plot for four cities ------------------------------
show <- intersect(c("Chennai", "Kolkata", "Mumbai", "Delhi"), names(res))
save_fig(function(mode) {
  p <- PAL[[mode]]
  curve <- bind_rows(lapply(show, function(cn) {
    f <- res[[cn]]$st
    T <- exp(seq(log(1.05), log(200), length.out = 120))
    out <- do.call(rbind, lapply(T, function(tt) gev_return_level(f, tt)))
    out$city <- cn; out$cat <- res[[cn]]$params$imd_category; out
  }))
  emp <- bind_rows(lapply(show, function(cn) {
    z <- sort(res[[cn]]$z); n <- length(z)
    data.frame(city = cn, T = 1 / (1 - (1:n) / (n + 1)), level = z,
               cat = res[[cn]]$params$imd_category)
  }))
  ggplot(curve, aes(T, level)) +
    geom_ribbon(aes(ymin = level - 1.96 * se, ymax = level + 1.96 * se, fill = cat),
                alpha = 0.25) +
    geom_line(aes(colour = cat), linewidth = 0.9) +
    geom_point(data = emp, aes(colour = cat), size = 1.6, alpha = 0.85) +
    geom_hline(yintercept = TW_CRITICAL, linetype = "22", colour = p$ink, linewidth = 0.4) +
    facet_wrap(~factor(city, show), nrow = 1) +
    scale_x_log10(breaks = c(2, 5, 10, 25, 50, 100)) +
    scale_colour_manual(values = cat_cols(mode), guide = "none") +
    scale_fill_manual(values = cat_cols(mode), guide = "none") +
    labs(x = "Return period (years, log scale)", y = "Annual max wet-bulb (°C)",
         caption = "GEV fitted by maximum likelihood (own optim code). Band = 95% delta-method CI; dots = observed annual maxima (Weibull plotting positions). Dashed = 31 °C.") +
    theme_b40(mode, base = 13)
}, "fig_return_levels", w = 12, h = 4.4)

# ---- Figure: GEV diagnostics for Chennai (probability & quantile plots) ----
save_fig(function(mode) {
  p <- PAL[[mode]]
  dc <- if ("Chennai" %in% names(res)) "Chennai" else names(res)[1]
  f <- res[[dc]]$st; z <- sort(res[[dc]]$z); n <- length(z)
  emp_p <- (1:n) / (n + 1)
  pp <- data.frame(model = pgev(z, f$par["mu"], f$par["sigma"], f$par["xi"]), emp = emp_p)
  qq <- data.frame(model = qgev(emp_p, f$par["mu"], f$par["sigma"], f$par["xi"]), emp = z)
  a <- ggplot(pp, aes(model, emp)) + geom_abline(colour = p$muted) +
    geom_point(colour = p$amber, size = 2) +
    labs(x = "Model probability", y = "Empirical probability", subtitle = "Probability plot") +
    theme_b40(mode)
  b <- ggplot(qq, aes(model, emp)) + geom_abline(colour = p$muted) +
    geom_point(colour = p$amber, size = 2) +
    labs(x = "Model quantile (°C)", y = "Empirical quantile (°C)", subtitle = "Quantile plot") +
    theme_b40(mode)
  a + b
}, "fig_gev_diagnostics_chennai", w = 9, h = 4.2)

message("GEV analysis done")
