# =============================================================================
# 09_early_warning.R  -  RQ5: can a simple probabilistic model warn of
# tomorrow's dangerous humid heat better than the IMD rule?
#   Logistic regression on today's weather; temporal hold-out (train 1981-2014,
#   test 2015-2025); Brier skill, ROC/AUC (DeLong CI), reliability diagram.
# =============================================================================

library(pROC)

d <- readRDS(path("data", "processed", "daily.rds"))

# Only cities where humid danger actually occurs (>= 20 danger days in 45 years);
# elsewhere the outcome is all-zero and the city effect is not estimable.
ew_cities <- d |> group_by(city) |> summarise(n = sum(danger)) |>
  filter(n >= 20) |> pull(city)

m <- d |>
  filter(city %in% ew_cities) |>
  arrange(city, date) |>
  group_by(city) |>
  mutate(next_danger = lead(danger), next_date = lead(date),
         tw_lag1 = lag(twmax), tw_change = twmax - lag(twmax)) |>
  ungroup() |>
  filter(month %in% 3:10, !is.na(next_danger), next_date == date + 1, !is.na(tw_lag1)) |>
  mutate(s1 = sin(2 * pi * doy / 365.25), c1 = cos(2 * pi * doy / 365.25),
         s2 = sin(4 * pi * doy / 365.25), c2 = cos(4 * pi * doy / 365.25),
         city = factor(city, intersect(CITIES$city, ew_cities)), year_c = (year - 2000) / 10,
         split = if_else(year <= 2014, "train", "test"))
train <- m |> filter(split == "train"); test <- m |> filter(split == "test")

# ---- Models ------------------------------------------------------------------
f_clim <- next_danger ~ city * (s1 + c1 + s2 + c2)
f_full <- next_danger ~ twmax + tw_change + tmax + rhmin + tmin + year_c +
  city + city:(s1 + c1 + s2 + c2)
clim <- glm(f_clim, family = binomial, data = train, control = glm.control(maxit = 100))
full <- glm(f_full, family = binomial, data = train, control = glm.control(maxit = 100))
stopifnot(clim$converged, full$converged)
# (A remaining "fitted probabilities 0 or 1" note is expected: on cool days the
#  chance of a 29 °C wet-bulb tomorrow is genuinely ~0. It does not bias the fit.)

pers <- train |> group_by(city, danger) |>
  summarise(p = mean(next_danger), .groups = "drop")
imd  <- train |> group_by(city, imd_heatwave) |>
  summarise(p = mean(next_danger), .groups = "drop")

test <- test |>
  mutate(p_clim = predict(clim, test, type = "response"),
         p_full = predict(full, test, type = "response")) |>
  left_join(pers |> rename(p_pers = p), by = c("city", "danger")) |>
  left_join(imd |> rename(p_imd = p), by = c("city", "imd_heatwave")) |>
  mutate(p_pers = coalesce(p_pers, p_clim), p_imd = coalesce(p_imd, p_clim))

brier <- function(p, y) mean((p - y)^2)
logloss <- function(p, y) { p <- pmin(pmax(p, 1e-6), 1 - 1e-6); -mean(y * log(p) + (1 - y) * log(1 - p)) }
y <- as.numeric(test$next_danger)
models <- c(Climatology = "p_clim", `IMD-rule state` = "p_imd",
            Persistence = "p_pers", `Logistic model` = "p_full")
rocs <- lapply(models, function(v) roc(y, test[[v]], quiet = TRUE, direction = "<"))
bs_clim <- brier(test$p_clim, y)
skill <- bind_rows(lapply(names(models), function(nm) {
  v <- models[[nm]]; ci <- ci.auc(rocs[[nm]], method = "delong")
  data.frame(model = nm, brier = brier(test[[v]], y),
             BSS_vs_climatology = 1 - brier(test[[v]], y) / bs_clim,
             log_loss = logloss(test[[v]], y),
             AUC = as.numeric(auc(rocs[[nm]])), AUC_lo = ci[1], AUC_hi = ci[3])
}))
save_table(skill, "early_warning_skill")

dl <- roc.test(rocs[["Logistic model"]], rocs[["Persistence"]], method = "delong")
save_table(data.frame(comparison = "Logistic vs persistence (DeLong)",
                      Z = unname(dl$statistic), p_value = dl$p.value),
           "early_warning_delong")

# Deterministic comparison at a fixed operating point:
# the IMD rule says "warn" if today is an IMD heatwave day
contingency <- function(warn, obs) {
  a <- sum(warn & obs); b <- sum(warn & !obs); c <- sum(!warn & obs)
  data.frame(hits = a, false_alarms = b, misses = c,
             POD = a / (a + c), FAR = if (a + b) b / (a + b) else NA,
             CSI = a / (a + b + c))
}
thr <- seq(0.05, 0.95, 0.01)
f1 <- sapply(thr, function(t) { k <- contingency(test$p_full >= t, y == 1)
                                2 * k$hits / (2 * k$hits + k$false_alarms + k$misses) })
best_t <- thr[which.max(f1)]
ops <- bind_rows(cbind(rule = "IMD heatwave today", contingency(test$imd_heatwave, y == 1)),
                 cbind(rule = "Danger today (persistence)", contingency(test$danger, y == 1)),
                 cbind(rule = sprintf("Logistic p ≥ %.2f (max F1)", best_t),
                       contingency(test$p_full >= best_t, y == 1)),
                 cbind(rule = "Logistic p ≥ 0.50", contingency(test$p_full >= 0.5, y == 1)))
save_table(ops, "early_warning_operating_points")

# Odds ratios of the interpretable weather terms
co <- summary(full)$coefficients
keep <- c("twmax", "tw_change", "tmax", "rhmin", "tmin", "year_c")
or <- data.frame(term = keep, coef = co[keep, 1], se = co[keep, 2], p_value = co[keep, 4],
                 odds_ratio = exp(co[keep, 1]),
                 OR_lo = exp(co[keep, 1] - 1.96 * co[keep, 2]),
                 OR_hi = exp(co[keep, 1] + 1.96 * co[keep, 2]))
save_table(or, "early_warning_odds_ratios")

# Reliability (calibration) table
rel <- test |> mutate(bin = cut(p_full, c(0, 0.02, 0.05, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 1),
                                include.lowest = TRUE)) |>
  group_by(bin) |>
  summarise(n = n(), mean_p = mean(p_full), obs = mean(next_danger), k = sum(next_danger),
            .groups = "drop") |>
  mutate(lo = wilson_ci(k, n)$lo, hi = wilson_ci(k, n)$hi)
save_table(rel, "early_warning_reliability")

# Slim model for the Shiny app
slim <- full
slim[c("data", "residuals", "fitted.values", "effects", "weights", "prior.weights",
       "linear.predictors", "y", "model")] <- NULL
slim$qr$qr <- NULL
attr(slim$terms, ".Environment") <- globalenv()   # don't drag the training data along
environment(slim$formula) <- globalenv()
saveRDS(list(model = slim, threshold = best_t, cities = ew_cities,
             stull_offset = d |> group_by(city) |>
               summarise(offset = mean(twmax - tw_stull, na.rm = TRUE))),
        path("outputs", "early_warning_model.rds"))

# ---- Figures ---------------------------------------------------------------
save_fig(function(mode) {
  p <- PAL[[mode]]
  cols <- c(Climatology = p$muted, `IMD-rule state` = p$blue,
            Persistence = "#8E7CC3", `Logistic model` = p$amber)
  rc <- bind_rows(lapply(names(rocs), function(nm)
    data.frame(model = nm, fpr = 1 - rocs[[nm]]$specificities,
               tpr = rocs[[nm]]$sensitivities))) |>
    mutate(model = factor(model, names(cols)))
  a <- ggplot(rc, aes(fpr, tpr, colour = model)) +
    geom_abline(colour = p$grid) + geom_path(linewidth = 0.9) +
    scale_colour_manual(values = cols,
                        labels = paste0(skill$model, "  (AUC ", sprintf("%.2f", skill$AUC), ")")) +
    labs(x = "False-positive rate", y = "Hit rate", subtitle = "ROC on 2015–2025 test years") +
    guides(colour = guide_legend(ncol = 2)) +
    theme_b40(mode) + theme(legend.position = "bottom", legend.text = element_text(size = 9.5))
  b <- ggplot(rel, aes(mean_p, obs)) +
    geom_abline(colour = p$muted, linetype = "22") +
    geom_errorbar(aes(ymin = lo, ymax = hi), colour = p$amber, width = 0.015) +
    geom_point(colour = p$amber, size = 2.8) +
    coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    labs(x = "Forecast probability", y = "Observed frequency",
         subtitle = "Reliability of the logistic model") +
    theme_b40(mode)
  a + b + plot_layout(widths = c(1.15, 1))
}, "fig_early_warning", w = 9.4, h = 5)

message("Early-warning model done")
