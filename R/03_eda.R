# =============================================================================
# 03_eda.R  -  descriptive statistics, correlation and the joint distribution
# of temperature and humidity
# =============================================================================

d <- readRDS(path("data", "processed", "daily.rds"))
city_order <- CITIES$city
d$city <- factor(d$city, levels = city_order)

skewness <- function(x) { x <- x[!is.na(x)]; mean((x - mean(x))^3) / sd(x)^3 }
kurtosis <- function(x) { x <- x[!is.na(x)]; mean((x - mean(x))^4) / sd(x)^4 - 3 }

hot <- d |> filter(month %in% 3:9)          # March-September: the hot half-year

# ---- 1. Descriptive statistics ----------------------------------------------
desc <- hot |>
  group_by(city, imd_category) |>
  summarise(mean_tmax = mean(tmax), sd_tmax = sd(tmax),
            mean_twmax = mean(twmax), sd_twmax = sd(twmax),
            median_twmax = median(twmax), iqr_twmax = IQR(twmax),
            max_twmax = max(twmax), skew_twmax = skewness(twmax),
            exkurt_twmax = kurtosis(twmax), mean_rhmin = mean(rhmin),
            .groups = "drop") |>
  left_join(d |> group_by(city, year) |>
              summarise(dd = sum(danger), hw = sum(imd_heatwave),
                        sd = sum(silent_danger), .groups = "drop") |>
              group_by(city) |>
              summarise(danger_days_per_yr = mean(dd), imd_hw_days_per_yr = mean(hw),
                        silent_days_per_yr = mean(sd)), by = "city")
save_table(desc, "descriptive_stats")

# ---- 2. Correlation: the hottest days are the driest days -------------------
cor_tab <- hot |>
  group_by(city) |>
  summarise(
    pearson_r  = cor.test(tmax, rhmin, method = "pearson")$estimate,
    pearson_p  = cor.test(tmax, rhmin, method = "pearson")$p.value,
    spearman_rho = suppressWarnings(cor.test(tmax, rhmin, method = "spearman")$estimate),
    spearman_p = suppressWarnings(cor.test(tmax, rhmin, method = "spearman")$p.value),
    .groups = "drop")
save_table(cor_tab, "correlation_tmax_rh")

# ---- 3. Multiple regression: what actually drives wet-bulb temperature? -----
# twmax ~ tmax + rhmin; standardised coefficients compare the two drivers
reg_tab <- do.call(rbind, lapply(split(hot, hot$city, drop = TRUE), function(x) {
  m  <- lm(twmax ~ tmax + rhmin, data = x)
  ms <- lm(scale(twmax) ~ scale(tmax) + scale(rhmin), data = x)
  ci <- confint(m)
  data.frame(city = x$city[1],
             b_tmax = coef(m)[2], b_tmax_lo = ci[2, 1], b_tmax_hi = ci[2, 2],
             b_rh10 = 10 * coef(m)[3], b_rh10_lo = 10 * ci[3, 1], b_rh10_hi = 10 * ci[3, 2],
             beta_tmax = coef(ms)[2], beta_rh = coef(ms)[3],
             r_squared = summary(m)$r.squared)
}))
rownames(reg_tab) <- NULL
save_table(reg_tab, "regression_wetbulb_drivers")

# ---- Figure: the blind spot in temperature-humidity space ------------------
tw_curve <- function(level) {
  t <- seq(26, 50, by = 0.05)
  rh <- sapply(t, function(tt) {
    f <- function(r) stull_wetbulb(tt, r) - level
    if (f(5) > 0 || f(99) < 0) return(NA_real_)
    uniroot(f, c(5, 99))$root
  })
  data.frame(tmax = t, rhmin = rh, level = level)
}
curves <- rbind(tw_curve(TW_DANGER), tw_curve(TW_CRITICAL)) |> filter(!is.na(rhmin))
iso_lab <- curves |> group_by(level) |> slice_min(abs(tmax - 46.8), n = 1) |>
  ungroup() |>
  mutate(lab = paste0("Tw = ", level, " °C"), vj = ifelse(level == TW_DANGER, 1.6, -0.7))

pts <- hot |>
  mutate(kind = case_when(imd_heatwave & danger ~ "Both",
                          imd_heatwave ~ "IMD heatwave day",
                          danger ~ "Dangerous humid heat (Tw ≥ 29 °C)",
                          TRUE ~ "Other day"))
set.seed(1)
bg_pts <- pts |> filter(kind == "Other day") |> slice_sample(n = 25000)
fg_pts <- pts |> filter(kind != "Other day")

save_fig(function(mode) {
  p <- PAL[[mode]]
  ggplot() +
    annotate("rect", xmin = 40, xmax = Inf, ymin = -Inf, ymax = Inf,
             fill = p$blue, alpha = 0.08) +
    geom_point(data = bg_pts, aes(tmax, rhmin), colour = p$grey, alpha = 0.06, size = 0.4) +
    geom_point(data = fg_pts |> filter(kind == "IMD heatwave day"),
               aes(tmax, rhmin, colour = kind), alpha = 0.35, size = 0.7) +
    geom_point(data = fg_pts |> filter(kind != "IMD heatwave day"),
               aes(tmax, rhmin, colour = kind), alpha = 0.35, size = 0.7) +
    geom_line(data = curves, aes(tmax, rhmin, group = level), colour = p$ink,
              linewidth = 0.5, linetype = "22") +
    annotate("text", x = 40.3, y = 97, label = "IMD plains rule: Tmax ≥ 40 °C",
             hjust = 0, colour = p$blue, family = FONT, size = 3.6) +
    geom_text(data = iso_lab, aes(tmax, rhmin, label = lab), colour = p$ink,
              family = FONT, size = 3.3, hjust = 0.5, vjust = iso_lab$vj) +
    scale_colour_manual(values = c("IMD heatwave day" = p$blue,
                                   "Dangerous humid heat (Tw ≥ 29 °C)" = p$amber,
                                   "Both" = p$ink),
                        breaks = c("IMD heatwave day",
                                   "Dangerous humid heat (Tw ≥ 29 °C)", "Both")) +
    guides(colour = guide_legend(override.aes = list(size = 3, alpha = 1))) +
    scale_x_continuous(limits = c(26, 49), breaks = seq(26, 48, 2)) +
    scale_y_continuous(limits = c(0, 100)) +
    labs(x = "Daily maximum temperature (°C)",
         y = "Daily minimum relative humidity (%)",
         caption = "10 cities, Mar–Sep 1981–2025, ERA5. Dashed lines: wet-bulb isotherms (Stull 2011).") +
    theme_sh(mode)
}, "fig_blindspot_scatter", w = 9, h = 5.9)

# ---- Figure: the two seasons barely overlap ---------------------------------
wk <- d |>
  mutate(week = pmin(52, (doy - 1) %/% 7 + 1)) |>
  group_by(city, imd_category, week) |>
  summarise(p_danger = mean(danger), p_imd = mean(imd_heatwave), .groups = "drop")
save_table(wk, "weekly_probabilities")

save_fig(function(mode) {
  p <- PAL[[mode]]
  pmax_all <- max(wk$p_imd, wk$p_danger)
  panel <- function(var, col, title) {
    ggplot(wk |> mutate(city = factor(city, rev(city_order))),
           aes(week, city, fill = .data[[var]])) +
      geom_tile(colour = p$bg, linewidth = 0.3) +
      scale_fill_gradient(low = if (mode == "dark") "#151515" else "#F4F4F4", high = col,
                          trans = "sqrt", limits = c(0, pmax_all), labels = percent,
                          breaks = c(0.01, 0.05, 0.1, 0.2), name = NULL) +
      scale_x_continuous(breaks = c(1, 9, 18, 27, 36, 44),
                         labels = c("Jan", "Mar", "May", "Jul", "Sep", "Nov"), expand = c(0, 0)) +
      labs(x = NULL, y = NULL, subtitle = title) +
      theme_sh(mode) +
      theme(panel.grid = element_blank(), legend.position = "bottom",
            legend.key.width = unit(1.6, "cm"), legend.key.height = unit(0.25, "cm"),
            plot.subtitle = element_text(colour = col, size = 14))
  }
  panel("p_imd", p$blue, "P(IMD heatwave day)") +
    (panel("p_danger", p$amber, "P(dangerous humid-heat day)") +
       theme(axis.text.y = element_blank())) +
    plot_annotation(caption = "Share of days in each calendar week, 1981–2025 (square-root colour scale).",
                    theme = theme_sh(mode))
}, "fig_season_calendar", w = 11, h = 5.2)

# ---- Figure: the distribution of daily max wet-bulb by city ------------------
save_fig(function(mode) {
  p <- PAL[[mode]]
  x <- hot |> filter(month %in% 4:6) |>
    mutate(city = factor(city, rev(city_order)))
  ggplot(x, aes(twmax, city, fill = imd_category)) +
    ggridges::geom_density_ridges(colour = p$bg, alpha = 0.9, scale = 1.6,
                                  linewidth = 0.3, rel_min_height = 0.005) +
    geom_vline(xintercept = c(TW_DANGER, TW_CRITICAL), colour = p$ink,
               linetype = "22", linewidth = 0.4) +
    annotate("text", x = TW_DANGER - 0.15, y = 11.1, label = "danger 29",
             colour = p$ink, hjust = 1, family = FONT, size = 3.3) +
    annotate("text", x = TW_CRITICAL + 0.15, y = 11.1, label = "critical 31",
             colour = p$ink, hjust = 0, family = FONT, size = 3.3) +
    scale_fill_manual(values = cat_cols(mode), labels = c(Plains = "Plains (40 °C rule)",
                                                          Coastal = "Coastal (37 °C rule)")) +
    scale_x_continuous(breaks = seq(14, 32, 2)) +
    coord_cartesian(clip = "off") +
    labs(x = "Daily maximum wet-bulb temperature, April–June (°C)", y = NULL) +
    theme_sh(mode)
}, "fig_wetbulb_ridges", w = 9, h = 6)

message("EDA done")
