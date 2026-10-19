# =============================================================================
# 06_trends.R  -  RQ2: is dangerous humid heat becoming more frequent?
#   Mann-Kendall + Sen's slope (own implementation, cross-checked with base R),
#   Poisson vs negative-binomial regression, era comparisons, two-way ANOVA
# =============================================================================

set.seed(2026)   # reproducible bootstrap / permutation / Monte Carlo draws
d <- readRDS(path("data", "processed", "daily.rds"))
counts <- readRDS(path("data", "processed", "annual_counts.rds"))

annual <- d |>
  group_by(city, imd_category, year) |>
  summarise(max_twmax = max(twmax),
            amj_twmax = mean(twmax[month %in% 4:6]), .groups = "drop") |>
  left_join(counts, by = c("city", "imd_category", "year"))
saveRDS(annual, path("data", "processed", "annual.rds"))

# ---- 1. Mann-Kendall per city, per indicator --------------------------------
indicators <- c(danger_days = "Danger days (Tw ≥ 29 °C)",
                silent_days = "Silent danger days",
                max_twmax   = "Annual max wet-bulb (°C)",
                amj_twmax   = "Apr–Jun mean of daily max wet-bulb (°C)")
mk <- do.call(rbind, lapply(split(annual, annual$city), function(x) {
  do.call(rbind, lapply(names(indicators), function(v) {
    y <- x[[v]]
    if (sum(y != 0) < 5) return(NULL)
    r <- mann_kendall(y)
    kt <- suppressWarnings(cor.test(y, x$year, method = "kendall", exact = FALSE))
    cbind(city = x$city[1], indicator = v, r,
          sen_per_decade = 10 * r$sen_slope,
          sen_lo_decade = 10 * r$sen_lo, sen_hi_decade = 10 * r$sen_hi,
          base_R_kendall_tau = unname(kt$estimate), base_R_p = kt$p.value)
  }))
}))
rownames(mk) <- NULL
save_table(mk, "trend_mann_kendall")

# ---- 2. Count regression: Poisson -> overdispersion -> negative binomial ----
# Cities with almost no danger days give all-zero series (perfect separation),
# so the count models use cities with at least 20 danger days in 45 years
count_cities <- annual |> group_by(city) |> summarise(n = sum(danger_days)) |>
  filter(n >= 20) |> pull(city)
cd <- annual |> filter(city %in% count_cities) |>
  mutate(decade_c = (year - 2000) / 10, city = factor(city))
pois <- glm(danger_days ~ decade_c + city, family = poisson, data = cd)
disp <- sum(residuals(pois, type = "pearson")^2) / pois$df.residual
nb   <- MASS::glm.nb(danger_days ~ decade_c + city, data = cd)
lrt  <- 2 * (as.numeric(logLik(nb)) - as.numeric(logLik(pois)))
ci   <- confint.default(nb)["decade_c", ]
count_model <- data.frame(
  model = c("Poisson", "Negative binomial"),
  AIC = c(AIC(pois), AIC(nb)),
  decade_coef = c(coef(pois)["decade_c"], coef(nb)["decade_c"]),
  IRR_per_decade = exp(c(coef(pois)["decade_c"], coef(nb)["decade_c"])),
  IRR_lo = exp(c(confint.default(pois)["decade_c", 1], ci[1])),
  IRR_hi = exp(c(confint.default(pois)["decade_c", 2], ci[2])),
  p_value = c(summary(pois)$coefficients["decade_c", 4],
              summary(nb)$coefficients["decade_c", 4]))
count_model$pearson_dispersion <- c(disp, NA)
count_model$LRT_vs_poisson <- c(NA, lrt)
count_model$LRT_p <- c(NA, 0.5 * pchisq(lrt, 1, lower.tail = FALSE))
count_model$theta <- c(NA, nb$theta)
save_table(count_model, "trend_count_models")

# Same model per IMD category: is the increase faster on the coast?
nb_cat <- NULL
if (length(unique(cd$imd_category)) > 1) {
  nb_cat <- MASS::glm.nb(danger_days ~ city + decade_c:imd_category, data = cd)
  inter <- summary(nb_cat)$coefficients
  save_table(data.frame(term = rownames(inter), inter, row.names = NULL),
             "trend_nb_interaction")
  # LRT: separate coastal/plains decade slopes vs one common slope
  lrt_cat <- 2 * (as.numeric(logLik(nb_cat)) - as.numeric(logLik(nb)))
  save_table(data.frame(test = "Separate coastal vs plains decade slopes (NB LRT)",
                        LRT = lrt_cat, df = 1,
                        p_value = pchisq(lrt_cat, 1, lower.tail = FALSE),
                        IRR_coastal = exp(coef(nb_cat)[["decade_c:imd_categoryCoastal"]]),
                        IRR_plains = exp(coef(nb_cat)[["decade_c:imd_categoryPlains"]])),
             "trend_nb_slope_test")
}
saveRDS(list(pois = pois, nb = nb, nb_cat = nb_cat),
        path("outputs", "tables", "count_models.rds"))

# ---- 3. Early vs recent era -----------------------------------------------------
perm_test <- function(a, b, R = 10000) {
  obs <- mean(b) - mean(a); pool <- c(a, b); na <- length(a)
  perm <- replicate(R, { s <- sample(pool); mean(s[-(1:na)]) - mean(s[1:na]) })
  c(diff = obs, p = (sum(abs(perm) >= abs(obs)) + 1) / (R + 1))
}
era <- do.call(rbind, lapply(split(annual, annual$city), function(x) {
  e1 <- x[x$year <= 2000, ]; e2 <- x[x$year >= 2006, ]
  daily1 <- d$twmax[d$city == x$city[1] & d$year <= 2000 & d$month %in% 4:6]
  daily2 <- d$twmax[d$city == x$city[1] & d$year >= 2006 & d$month %in% 4:6]
  w  <- suppressWarnings(wilcox.test(e2$danger_days, e1$danger_days, exact = FALSE))
  tt <- t.test(e2$amj_twmax, e1$amj_twmax)                   # Welch
  ks <- suppressWarnings(ks.test(daily2, daily1))
  pm <- perm_test(e1$danger_days, e2$danger_days)
  data.frame(city = x$city[1],
             danger_days_1981_2000 = mean(e1$danger_days),
             danger_days_2006_2025 = mean(e2$danger_days),
             wilcoxon_W = unname(w$statistic), wilcoxon_p = w$p.value,
             perm_diff = pm["diff"], perm_p = pm["p"],
             amj_tw_1981_2000 = mean(e1$amj_twmax), amj_tw_2006_2025 = mean(e2$amj_twmax),
             welch_t = unname(tt$statistic), welch_df = unname(tt$parameter),
             welch_p = tt$p.value, welch_lo = tt$conf.int[1], welch_hi = tt$conf.int[2],
             ks_D = unname(ks$statistic), ks_p = ks$p.value)
}))
rownames(era) <- NULL
save_table(era, "trend_era_comparison")

# ---- 4. Two-way ANOVA: city and decade effects on Apr-Jun wet-bulb ----------
av_d <- annual |>
  mutate(decade = cut(year, c(1980, 1990, 2000, 2010, 2020, 2025),
                      labels = c("1981–90", "1991–2000", "2001–10", "2011–20", "2021–25")))
av <- aov(amj_twmax ~ city + decade, data = av_d)
av_tab <- summary(av)[[1]]
save_table(data.frame(term = trimws(rownames(av_tab)), av_tab, row.names = NULL),
           "anova_city_decade")
tk <- TukeyHSD(av, "decade")$decade
save_table(data.frame(comparison = rownames(tk), tk, row.names = NULL), "anova_tukey_decade")
assump <- data.frame(
  test = c("Shapiro-Wilk on residuals", "Bartlett homogeneity (decade)"),
  statistic = c(shapiro.test(residuals(av))$statistic,
                bartlett.test(residuals(av) ~ av_d$decade)$statistic),
  p_value = c(shapiro.test(residuals(av))$p.value,
              bartlett.test(residuals(av) ~ av_d$decade)$p.value))
# Residuals are not perfectly normal/homoscedastic, so confirm with the
# distribution-free Friedman test (blocks = cities, treatments = decades)
fm <- av_d |> group_by(city, decade) |> summarise(y = mean(amj_twmax), .groups = "drop")
fr <- friedman.test(y ~ decade | city, data = fm)
kw <- kruskal.test(amj_twmax ~ decade, data = av_d)
assump <- rbind(assump, data.frame(
  test = c("Friedman (decade | city), robustness", "Kruskal-Wallis (decade), robustness"),
  statistic = c(unname(fr$statistic), unname(kw$statistic)),
  p_value = c(fr$p.value, kw$p.value)))
save_table(assump, "anova_assumptions")

# ---- Figures ---------------------------------------------------------------
save_fig(function(mode) {
  p <- PAL[[mode]]
  x <- annual |> filter(city %in% count_cities) |>
    mutate(city = factor(city, CITIES$city))
  # Zero-heavy counts make the Sen (median) slope collapse to 0, so the drawn
  # trend is a per-city negative-binomial fit; p-values are from Mann-Kendall
  fits <- bind_rows(lapply(split(x, droplevels(x$city)), function(xc) {
    m <- tryCatch(MASS::glm.nb(danger_days ~ I((year - 2000) / 10), data = xc),
                  error = function(e) glm(danger_days ~ I((year - 2000) / 10),
                                          family = poisson, data = xc))
    data.frame(city = xc$city[1], year = xc$year, fit = fitted(m),
               irr = exp(coef(m)[2]))
  }))
  lab <- mk |> filter(indicator == "danger_days", city %in% count_cities) |>
    mutate(city = factor(city, CITIES$city)) |>
    left_join(fits |> distinct(city, irr), by = "city") |>
    mutate(txt = sprintf("×%.2f per decade\nMK p %s", irr, fmt_p(p_value)))
  ggplot(x, aes(year, danger_days)) +
    geom_col(aes(fill = imd_category), width = 0.8) +
    geom_line(data = fits, aes(year, fit), colour = p$ink, linewidth = 0.7) +
    geom_text(data = lab, aes(x = 1981, y = Inf, label = txt), hjust = 0, vjust = 1.2,
              colour = p$ink, family = FONT, size = 3.6, lineheight = 0.9) +
    facet_wrap(~city, ncol = 5, scales = "free_y") +
    scale_fill_manual(values = cat_cols(mode), guide = "none") +
    scale_x_continuous(breaks = c(1985, 2005, 2025)) +
    labs(x = NULL, y = "Danger days per year (Tw ≥ 29 °C)",
         caption = "Cities with ≥ 20 danger days. Line = negative-binomial trend (×IRR per decade); p = Mann–Kendall test (own implementation, tie-corrected).") +
    theme_sh(mode, base = 13)
}, "fig_trend_counts", w = 12, h = 4.3)

save_fig(function(mode) {
  p <- PAL[[mode]]
  m <- av_d |> group_by(decade, imd_category) |>
    summarise(mean = mean(amj_twmax), se = sd(amj_twmax) / sqrt(n()), .groups = "drop")
  ggplot(m, aes(decade, mean, colour = imd_category, group = imd_category)) +
    geom_line(linewidth = 0.8) +
    geom_errorbar(aes(ymin = mean - 1.96 * se, ymax = mean + 1.96 * se), width = 0.12) +
    geom_point(size = 3) +
    scale_colour_manual(values = cat_cols(mode),
                        labels = c(Plains = "Plains cities", Coastal = "Coastal cities")) +
    labs(x = NULL, y = "Apr–Jun mean daily max wet-bulb (°C)",
         caption = "Mean ± 95% CI of city-year values.") +
    theme_sh(mode)
}, "fig_decade_means", w = 8, h = 5)

message("Trend analysis done")
