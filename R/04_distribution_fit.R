# =============================================================================
# 04_distribution_fit.R  -  which probability model describes humid heat?
#   (a) continuous: daily max wet-bulb in May  -> Normal / Gamma / Weibull / Lognormal
#   (b) discrete:   annual count of danger days -> Poisson vs Negative Binomial
# =============================================================================

library(fitdistrplus)

d <- readRDS(path("data", "processed", "daily.rds"))

# ---- (a) Continuous fits by maximum likelihood --------------------------------
fit_one_city <- function(x) {
  fits <- list(Normal    = fitdist(x, "norm"),
               Gamma     = fitdist(x, "gamma"),
               Weibull   = fitdist(x, "weibull"),
               Lognormal = fitdist(x, "lnorm"))
  g <- gofstat(fits, fitnames = names(fits))
  list(fits = fits,
       table = data.frame(distribution = names(fits),
                          loglik = sapply(fits, `[[`, "loglik"),
                          AIC = unname(g$aic), BIC = unname(g$bic),
                          KS = unname(g$ks), AD = unname(g$ad)))
}

may <- d |> filter(month == 5)
cont <- lapply(split(may$twmax, may$city), fit_one_city)
cont_tab <- do.call(rbind, lapply(names(cont), function(cn)
  cbind(city = cn, cont[[cn]]$table))) |>
  group_by(city) |>
  mutate(delta_AIC = AIC - min(AIC), best = delta_AIC == 0) |>
  ungroup()
save_table(cont_tab, "dist_fit_continuous")

# Formal goodness-of-fit for the Normal model (one-sample KS against the MLE;
# p-values are approximate because parameters are estimated and days are
# autocorrelated - which is why AIC is the primary criterion)
ks_tab <- do.call(rbind, lapply(split(may$twmax, may$city), function(x) {
  k <- suppressWarnings(ks.test(x, "pnorm", mean(x), sd(x)))
  s <- shapiro.test(sample(x, min(5000, length(x))))
  data.frame(KS_D = unname(k$statistic), KS_p = k$p.value,
             shapiro_W = unname(s$statistic), shapiro_p = s$p.value)
}))
ks_tab$city <- rownames(ks_tab); rownames(ks_tab) <- NULL
save_table(ks_tab, "normality_tests_may")

# Figure: Chennai and Delhi, histogram + fitted densities + Q-Q of the Normal
show <- intersect(c("Chennai", "Delhi"), names(cont))
save_fig(function(mode) {
  p <- PAL[[mode]]
  dens <- do.call(rbind, lapply(show, function(cn) {
    x <- may$twmax[may$city == cn]; f <- cont[[cn]]$fits
    g <- seq(min(x) - 1, max(x) + 1, length.out = 300)
    rbind(data.frame(city = cn, x = g, model = "Normal",
                     y = dnorm(g, f$Normal$estimate[1], f$Normal$estimate[2])),
          data.frame(city = cn, x = g, model = "Gamma",
                     y = dgamma(g, f$Gamma$estimate[1], f$Gamma$estimate[2])),
          data.frame(city = cn, x = g, model = "Weibull",
                     y = dweibull(g, f$Weibull$estimate[1], f$Weibull$estimate[2])))
  }))
  cols <- c(Normal = p$muted, Gamma = p$blue, Weibull = p$amber)
  h <- ggplot(may |> filter(city %in% show), aes(twmax)) +
    geom_histogram(aes(y = after_stat(density)), binwidth = 0.5,
                   fill = p$grid, colour = p$bg) +
    geom_line(data = dens, aes(x, y, colour = model), linewidth = 0.8) +
    facet_wrap(~city, scales = "free") +
    scale_colour_manual(values = cols, breaks = names(cols)) +
    labs(x = "Daily max wet-bulb temperature in May (°C)", y = "Density") +
    theme_b40(mode)
  q <- ggplot(may |> filter(city %in% show), aes(sample = twmax)) +
    stat_qq(colour = p$amber, size = 0.6, alpha = 0.6) +
    stat_qq_line(colour = p$ink, linewidth = 0.5) +
    facet_wrap(~city, scales = "free") +
    labs(x = "Theoretical Normal quantile", y = "Sample quantile (°C)") +
    theme_b40(mode)
  h / q + plot_layout(heights = c(1.1, 1))
}, "fig_distribution_fits", w = 8, h = 6)

# ---- (b) Annual counts: Poisson vs Negative Binomial ------------------------
counts <- d |> group_by(city, imd_category, year) |>
  summarise(danger_days = sum(danger), silent_days = sum(silent_danger),
            critical_days = sum(critical), imd_days = sum(imd_heatwave),
            .groups = "drop")
saveRDS(counts, path("data", "processed", "annual_counts.rds"))

count_tab <- do.call(rbind, lapply(split(counts, counts$city), function(x) {
  y <- x$danger_days; n <- length(y)
  if (sum(y) < 5) return(NULL)
  D <- (n - 1) * var(y) / mean(y)                 # dispersion index ~ chi^2_{n-1}
  ll_pois <- sum(dpois(y, mean(y), log = TRUE))
  nb <- tryCatch(suppressWarnings(MASS::fitdistr(y, "negative binomial")),
                 error = function(e) NULL)
  ll_nb <- if (is.null(nb)) NA else nb$loglik
  lrt <- 2 * (ll_nb - ll_pois)                    # boundary LRT: 0.5*chi^2_1
  data.frame(city = x$city[1], mean = mean(y), variance = var(y),
             var_to_mean = var(y) / mean(y), dispersion_stat = D,
             dispersion_p = pchisq(D, n - 1, lower.tail = FALSE),
             AIC_poisson = -2 * ll_pois + 2, AIC_negbin = -2 * ll_nb + 4,
             LRT = lrt, LRT_p = 0.5 * pchisq(lrt, 1, lower.tail = FALSE),
             nb_size = if (is.null(nb)) NA else unname(nb$estimate["size"]))
}))
save_table(count_tab, "dist_fit_counts")

message("Distribution fitting done")
