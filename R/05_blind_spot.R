# =============================================================================
# 05_blind_spot.R  -  RQ1: how many dangerous humid-heat days does the IMD
# heatwave rule miss, and is the miss rate the same everywhere?
# =============================================================================

set.seed(2026)   # reproducible bootstrap / permutation / Monte Carlo draws
d <- readRDS(path("data", "processed", "daily.rds"))
B <- 2000

block_boot_miss <- function(x, B) {
  # Resample whole years (block bootstrap) to respect day-to-day dependence
  yrs <- unique(x$year)
  by_year <- x |> group_by(year) |>
    summarise(n = sum(danger), m = sum(silent_danger), .groups = "drop")
  reps <- replicate(B, {
    s <- by_year[sample(nrow(by_year), replace = TRUE), ]
    if (sum(s$n) == 0) NA else sum(s$m) / sum(s$n)
  })
  quantile(reps, c(0.025, 0.975), na.rm = TRUE)
}

rows <- lapply(split(d, d$city), function(x) {
  tab <- table(IMD = factor(x$imd_heatwave, c(TRUE, FALSE)),
               Danger = factor(x$danger, c(TRUE, FALSE)))
  n  <- sum(x$danger); m <- sum(x$silent_danger)
  hi_catch <- sum(x$danger & x$hi_band %in% c("Orange", "Red"))
  base <- data.frame(city = x$city[1], imd_category = x$imd_category[1],
                     days = nrow(x), imd_days = sum(x$imd_heatwave),
                     danger_days = n, critical_days = sum(x$critical),
                     both = tab["TRUE", "TRUE"], silent = m)
  if (n < 10) return(cbind(base, miss_rate = NA))
  w  <- wilson_ci(m, n)
  ex <- binom.test(m, n)$conf.int
  bb <- block_boot_miss(x, B)
  # Bayesian: Beta(1,1) prior + binomial likelihood -> Beta(1+m, 1+n-m)
  a <- 1 + m; b <- 1 + n - m
  chi <- suppressWarnings(chisq.test(tab))
  use_fisher <- any(chi$expected < 5)
  assoc_p <- if (use_fisher) fisher.test(tab)$p.value else chi$p.value
  cbind(base,
        miss_rate = m / n, wilson_lo = w$lo, wilson_hi = w$hi,
        exact_lo = ex[1], exact_hi = ex[2], boot_lo = bb[1], boot_hi = bb[2],
        bayes_mean = a / (a + b), bayes_lo = qbeta(0.025, a, b), bayes_hi = qbeta(0.975, a, b),
        p_miss_gt_90 = pbeta(0.9, a, b, lower.tail = FALSE),
        kappa = cohens_kappa(tab),
        assoc_test = if (use_fisher) "Fisher exact" else "Chi-square",
        assoc_stat = if (use_fisher) NA else unname(chi$statistic),
        assoc_p = assoc_p,
        mcnemar_stat = unname(mcnemar.test(tab)$statistic),
        mcnemar_p = mcnemar.test(tab)$p.value,
        hi_orange_capture = hi_catch / n,
        silent_per_year = m / length(unique(x$year)))
})
blind <- bind_rows(rows)
rownames(blind) <- NULL
save_table(blind, "blind_spot_by_city")

# ---- Pooled tests --------------------------------------------------------------
dd <- d |> filter(danger)
pooled <- list(
  n_danger = nrow(dd), n_silent = sum(dd$silent_danger),
  miss_rate = mean(dd$silent_danger),
  wilson = wilson_ci(sum(dd$silent_danger), nrow(dd)),
  n_critical = sum(d$critical), n_critical_silent = sum(d$critical & !d$imd_heatwave),
  hi_orange_capture = mean(dd$hi_band %in% c("Orange", "Red")),
  imd_days = sum(d$imd_heatwave),
  imd_days_humid = sum(d$imd_heatwave & d$danger)
)

# Homogeneity of miss rates across cities (chi-square on city x caught/missed)
hom_tab <- table(dd$city, dd$silent_danger)
pooled$homogeneity <- if (ncol(hom_tab) == 2) {
  h <- suppressWarnings(chisq.test(hom_tab))
  if (any(h$expected < 5)) {
    h <- suppressWarnings(chisq.test(hom_tab, simulate.p.value = TRUE, B = 1e4))
  }
  h
} else NULL

# Coastal vs plains: two-proportion test on the share of danger days that are silent
cp <- dd |> group_by(imd_category) |>
  summarise(n = n(), silent = sum(silent_danger), .groups = "drop")
pooled$coastal_vs_plains <- prop.test(cp$silent, cp$n)
pooled$cp_table <- cp

# Where do IMD heatwaves and humid danger overlap at all? Joint probabilities
pooled$joint <- with(d, prop.table(table(IMD = imd_heatwave, Danger = danger)))

# ---- Sensitivity: does the conclusion depend on the 29 °C threshold? --------
# Absolute thresholds 27-30 °C plus *local* thresholds (each city's own 95th
# and 99th percentile of daily max wet-bulb) - the "locally defined threshold"
# that heat-action-plan reviews ask for.
thr_defs <- list(`Tw ≥ 27` = function(x) x >= 27, `Tw ≥ 28` = function(x) x >= 28,
                 `Tw ≥ 29` = function(x) x >= 29, `Tw ≥ 30` = function(x) x >= 30,
                 `Local P95` = function(x) x >= quantile(x, 0.95),
                 `Local P99` = function(x) x >= quantile(x, 0.99))
sens <- d |>
  group_by(city, imd_category) |>
  group_modify(function(x, key) bind_rows(lapply(names(thr_defs), function(nm) {
    flag <- thr_defs[[nm]](x$twmax)
    n <- sum(flag); m <- sum(flag & !x$imd_heatwave)
    data.frame(threshold = nm, n_days = n, missed = m,
               miss_rate = if (n > 0) m / n else NA_real_)
  }))) |>
  ungroup()
save_table(sens, "blind_spot_sensitivity")
pooled$sensitivity_pooled <- sens |> group_by(threshold) |>
  summarise(n_days = sum(n_days), missed = sum(missed), miss_rate = missed / n_days)

save_fig(function(mode) {
  p <- PAL[[mode]]
  x <- sens |> mutate(city = factor(city, rev(CITIES$city)),
                      threshold = factor(threshold, names(thr_defs)),
                      lab = ifelse(n_days == 0, "–", paste0(round(100 * miss_rate), "%")))
  ggplot(x, aes(threshold, city, fill = miss_rate)) +
    geom_tile(colour = p$bg, linewidth = 1.2) +
    geom_text(aes(label = lab), colour = ifelse(is.na(x$miss_rate) | x$miss_rate < 0.6,
                                                p$ink, "#111111"),
              family = FONT, size = 3.6) +
    scale_fill_gradient(low = p$grid, high = p$amber, limits = c(0, 1),
                        labels = percent, na.value = p$bg, name = "Miss rate") +
    scale_x_discrete(labels = function(x) sub(" ", "\n", x)) +
    labs(x = "Definition of a dangerous humid-heat day", y = NULL,
         caption = "Cell = share of flagged days that were not IMD heatwave days, 1981–2025\n(day counts per cell in blind_spot_sensitivity.csv).") +
    theme_b40(mode) +
    theme(panel.grid = element_blank(), legend.position = "right")
}, "fig_sensitivity", w = 7.4, h = 5.9)

saveRDS(pooled, path("outputs", "tables", "blind_spot_pooled.rds"))
save_table(data.frame(
  n_danger = pooled$n_danger, n_silent = pooled$n_silent, miss_rate = pooled$miss_rate,
  wilson_lo = pooled$wilson$lo, wilson_hi = pooled$wilson$hi,
  n_critical = pooled$n_critical, imd_days = pooled$imd_days,
  imd_days_humid = pooled$imd_days_humid, hi_orange_capture = pooled$hi_orange_capture,
  homogeneity_p = if (is.null(pooled$homogeneity)) NA else pooled$homogeneity$p.value,
  coastal_vs_plains_p = pooled$coastal_vs_plains$p.value,
  city_days = nrow(d)), "blind_spot_pooled_summary")
capture.output(print(pooled), file = path("outputs", "tables", "blind_spot_pooled.txt"))

# ---- Figure: miss rate with three kinds of interval ---------------------------
save_fig(function(mode) {
  p <- PAL[[mode]]
  x <- blind |> filter(!is.na(miss_rate)) |>
    mutate(city = reorder(city, miss_rate))
  ggplot(x, aes(y = city, colour = imd_category)) +
    geom_segment(aes(x = boot_lo, xend = boot_hi, yend = city), linewidth = 2.2,
                 alpha = 0.45, lineend = "round") +
    geom_point(aes(x = miss_rate), size = 3.6) +
    geom_text(aes(x = pmin(boot_lo, miss_rate) - 0.012,
                  label = paste0(danger_days, " danger days")),
              hjust = 1, colour = p$muted, family = FONT, size = 3.2) +
    scale_x_continuous(labels = percent, limits = c(min(x$boot_lo, na.rm = TRUE) - 0.2, 1),
                       breaks = seq(0, 1, 0.1)) +
    scale_colour_manual(values = cat_cols(mode),
                        labels = c(Plains = "Plains (40 °C rule)", Coastal = "Coastal (37 °C rule)")) +
    labs(x = "Share of dangerous humid-heat days (Tw ≥ 29 °C) that were NOT IMD heatwave days",
         y = NULL,
         caption = "Point = estimate; bar = 95% year-block bootstrap interval (2000 resamples). 1981–2025.") +
    theme_b40(mode)
}, "fig_miss_rate", w = 10, h = 5.6)

# ---- Figure: per-year counts, IMD days vs silent danger days ----------------
save_fig(function(mode) {
  p <- PAL[[mode]]
  x <- blind |>
    transmute(city, imd = imd_days / 45, silent = silent / 45) |>
    pivot_longer(c(imd, silent), names_to = "type", values_to = "days") |>
    mutate(type = factor(type, c("imd", "silent"),
                         c("IMD heatwave days / year", "Silent danger days / year")),
           city = factor(city, rev(CITIES$city)))
  ggplot(x, aes(days, city, fill = type)) +
    geom_col(position = position_dodge(width = 0.75), width = 0.7) +
    geom_text(aes(label = sprintf("%.1f", days)), position = position_dodge(width = 0.75),
              hjust = -0.2, colour = p$ink, family = FONT, size = 3.1) +
    scale_fill_manual(values = c(p$blue, p$amber)) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(x = "Average days per year, 1981–2025", y = NULL) +
    theme_b40(mode)
}, "fig_days_per_year", w = 8, h = 5.9)

message("Blind-spot analysis done")
