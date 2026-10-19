# =============================================================================
# 11_ml_models.R  -  ML extension of RQ5: baseline classifiers for humid-heat
# early warning, 1-3 days ahead.
#   Models: logistic regression, decision tree (rpart), random forest (ranger),
#   against climatology and the IMD rule. Same temporal hold-out as RQ5
#   (train 1981-2014, test 2015-2025); thresholds tuned on 2010-2014 only.
# Novelty: (1) physiology-informed "headroom" features (distance of wet-bulb
#   to the 29 °C limit and how fast it is closing), (2) a hybrid alert that
#   keeps the IMD rule and adds an ML humid-heat layer, scored on how much of
#   the blind spot it recovers, and (3) leave-one-city-out transfer: can the
#   warning run in a city with no labelled history?
# =============================================================================

library(pROC)
library(rpart)
library(ranger)

d <- readRDS(path("data", "processed", "daily.rds"))
ew_cities <- d |> group_by(city) |> summarise(n = sum(danger)) |>
  filter(n >= 20) |> pull(city)

# ---- Features ------------------------------------------------------------------
base <- d |>
  filter(city %in% ew_cities) |>
  arrange(city, date) |>
  group_by(city) |>
  mutate(tw_lag1 = lag(twmax), tw_lag2 = lag(twmax, 2),
         tw_change = twmax - tw_lag1,
         tw_roll3 = (twmax + tw_lag1 + tw_lag2) / 3,
         tw_max7 = pmax(twmax, lag(twmax), lag(twmax, 2), lag(twmax, 3),
                        lag(twmax, 4), lag(twmax, 5), lag(twmax, 6)),
         rh_change = rhmin - lag(rhmin),
         # physiology-informed: headroom to the danger limit and its closing speed
         headroom = TW_DANGER - twmax,
         closing = (tw_roll3 - lag(tw_roll3, 3)) / 3,
         days_to_limit = pmin(pmax(headroom, 0) / pmax(closing, 0.05), 30),
         danger_days7 = danger + lag(danger) + lag(danger, 2) + lag(danger, 3) +
           lag(danger, 4) + lag(danger, 5) + lag(danger, 6)) |>
  ungroup() |>
  mutate(s1 = sin(2 * pi * doy / 365.25), c1 = cos(2 * pi * doy / 365.25),
         s2 = sin(4 * pi * doy / 365.25), c2 = cos(4 * pi * doy / 365.25),
         year_c = (year - 2000) / 10, coastal = as.numeric(imd_category == "Coastal"),
         city = factor(city, intersect(CITIES$city, ew_cities)))

feats <- c("twmax", "twmean", "tmax", "tmin", "rhmin", "rhmean", "heat_index", "departure",
           "tw_lag1", "tw_lag2", "tw_change", "tw_roll3", "tw_max7", "rh_change",
           "headroom", "closing", "days_to_limit", "danger_days7",
           "s1", "c1", "s2", "c2", "year_c")
geo <- c("grid_lat", "elevation", "coastal")   # used instead of city in transfer

make_set <- function(h) {
  base |>
    group_by(city) |>
    mutate(y = lead(danger, h), y_date = lead(date, h), imd_target = lead(imd_heatwave, h)) |>
    ungroup() |>
    filter(month %in% 3:10, !is.na(y), y_date == date + h,
           if_all(all_of(feats), ~ !is.na(.x))) |>
    mutate(yf = factor(if_else(y, "yes", "no"), c("no", "yes")))
}

# ---- Model zoo -----------------------------------------------------------------
fit_predict <- function(train, test, use_city = TRUE) {
  x <- c(feats, if (use_city) "city" else geo)
  f <- reformulate(x, "yf")
  f_lr <- reformulate(c(setdiff(x, "city"), if (use_city) "city"), "y")
  # climatology: training-period danger frequency by city (or coast type) and month
  key <- if (use_city) "city" else "coastal"
  clim <- train |> group_by(across(all_of(c(key, "month")))) |>
    summarise(p_clim = mean(y), .groups = "drop")
  lr <- suppressWarnings(glm(f_lr, binomial, train, control = glm.control(maxit = 100)))
  # probability tree: regression on 0/1 (Brier loss); a class tree on 2%
  # positives never beats the all-"no" root and prunes to nothing
  tr <- rpart(reformulate(x, "y"), train, method = "anova",
              control = rpart.control(cp = 5e-4, minbucket = 40, xval = 5))
  tr <- prune(tr, cp = tr$cptable[which.min(tr$cptable[, "xerror"]), "CP"])
  rf <- ranger(f, train, num.trees = 400, min.node.size = 25, probability = TRUE,
               importance = "permutation", num.threads = 8, seed = 2026)
  list(models = list(lr = lr, tree = tr, rf = rf),
       p = data.frame(Climatology = coalesce(left_join(test, clim, by = c(key, "month"))$p_clim, 0),
                      Logistic = predict(lr, test, type = "response"),
                      `Decision tree` = predict(tr, test),
                      `Random forest` = predict(rf, test)$predictions[, "yes"],
                      check.names = FALSE))
}

brier <- function(p, y) mean((p - y)^2)
avg_prec <- function(p, y) {          # area under the precision-recall curve
  o <- order(p, decreasing = TRUE); y <- y[o]
  sum(cumsum(y) / seq_along(y) * y) / sum(y)
}
contingency <- function(warn, obs) {
  a <- sum(warn & obs); b <- sum(warn & !obs); c <- sum(!warn & obs)
  data.frame(hits = a, false_alarms = b, misses = c, POD = a / (a + c),
             FAR = if (a + b) b / (a + b) else NA, CSI = a / (a + b + c))
}
best_f1 <- function(p, y) {
  thr <- seq(0.03, 0.9, 0.01)
  f1 <- sapply(thr, function(t) { k <- contingency(p >= t, y == 1)
                                  2 * k$hits / (2 * k$hits + k$false_alarms + k$misses) })
  thr[which.max(f1)]
}
ml_models <- c("Logistic", "Decision tree", "Random forest")

# ---- 1. Multi-lead comparison ------------------------------------------------------
results <- list(); hybrid <- list(); keep <- list()
for (h in 1:3) {
  m <- make_set(h)
  train <- filter(m, year <= 2014); test <- filter(m, year >= 2015)
  # thresholds from a validation window that the final models never test on
  val <- fit_predict(filter(train, year <= 2009), filter(train, year >= 2010))
  thr <- sapply(ml_models, function(nm) best_f1(val$p[[nm]], filter(train, year >= 2010)$y))
  fit <- fit_predict(train, test)
  y <- as.numeric(test$y); bs_clim <- brier(fit$p$Climatology, y)

  results[[h]] <- bind_rows(lapply(names(fit$p), function(nm) {
    p <- fit$p[[nm]]; r <- roc(y, p, quiet = TRUE, direction = "<"); ci <- ci.auc(r)
    data.frame(lead_days = h, model = nm, AUC = as.numeric(auc(r)), AUC_lo = ci[1],
               AUC_hi = ci[3], PR_AUC = avg_prec(p, y), brier = brier(p, y),
               BSS = 1 - brier(p, y) / bs_clim)
  }))

  # Hybrid alert: keep the IMD rule, add the ML layer. Blind-spot recovery =
  # share of next-day danger days the IMD rule would not flag that we catch.
  silent <- test$y & !test$imd_target
  rules <- c(list(`IMD rule alone` = test$imd_heatwave),
             setNames(lapply(ml_models, function(nm) fit$p[[nm]] >= thr[[nm]]), ml_models),
             list(`Hybrid: IMD + RF` = test$imd_heatwave | fit$p$`Random forest` >= thr[["Random forest"]]))
  hybrid[[h]] <- bind_rows(lapply(names(rules), function(nm)
    cbind(lead_days = h, rule = nm, contingency(rules[[nm]], test$y),
          blind_spot_recovered = sum(rules[[nm]] & silent) / sum(silent))))
  if (h == 1) keep <- list(fit = fit, train = train, test = test, thr = thr)
}
ml_skill <- bind_rows(results); save_table(ml_skill, "ml_skill_by_lead")
ml_hybrid <- bind_rows(hybrid); save_table(ml_hybrid, "ml_hybrid_alerts")

imp <- sort(keep$fit$models$rf$variable.importance, decreasing = TRUE)
ml_imp <- data.frame(feature = names(imp), importance = unname(imp))
save_table(ml_imp, "ml_rf_importance")

# ---- 2. Leave-one-city-out transfer (lead 1) -------------------------------------
m1 <- make_set(1)
loco <- bind_rows(lapply(ew_cities, function(cc) {
  tr <- filter(m1, year <= 2014, city != cc); te <- filter(m1, year >= 2015, city == cc)
  pp <- fit_predict(tr, te, use_city = FALSE)$p
  own <- keep$fit$p[keep$test$city == cc, ]
  yo <- as.numeric(keep$test$y[keep$test$city == cc])
  bind_rows(lapply(ml_models, function(nm) data.frame(
    city = cc, model = nm, n_danger = sum(te$y),
    AUC_unseen = as.numeric(auc(roc(as.numeric(te$y), pp[[nm]], quiet = TRUE, direction = "<"))),
    AUC_seen = as.numeric(auc(roc(yo, own[[nm]], quiet = TRUE, direction = "<"))))))
}))
save_table(loco, "ml_loco_transfer")

# ---- Figures ---------------------------------------------------------------------
mod_cols <- function(p) c(Climatology = p$muted, Logistic = p$blue,
                          `Decision tree` = "#8E7CC3", `Random forest` = p$amber)

save_fig(function(mode) {
  p <- PAL[[mode]]; cols <- mod_cols(p)
  a <- ggplot(ml_skill |> mutate(model = factor(model, names(cols))),
              aes(lead_days, AUC, colour = model)) +
    geom_errorbar(aes(ymin = AUC_lo, ymax = AUC_hi), width = 0.06,
                  position = position_dodge(0.25)) +
    geom_line(position = position_dodge(0.25), linewidth = 0.8) +
    geom_point(position = position_dodge(0.25), size = 2.6) +
    scale_colour_manual(values = cols, name = NULL) +
    scale_x_continuous(breaks = 1:3, labels = paste0("+", 1:3, " day")) +
    labs(x = "Warning lead time", y = "AUC (95% CI)", subtitle = "Test years 2015–2025") +
    theme_b40(mode) + theme(legend.position = "bottom")
  top <- head(ml_imp, 10) |> mutate(feature = factor(feature, rev(feature)),
                                    novel = feature %in% c("headroom", "closing", "days_to_limit", "danger_days7"))
  b <- ggplot(top, aes(importance, feature, fill = novel)) + geom_col(width = 0.7) +
    scale_fill_manual(values = c(`FALSE` = p$grey, `TRUE` = p$amber),
                      labels = c("Weather", "Physiology-informed"), name = NULL) +
    labs(x = "Permutation importance", y = NULL, subtitle = "Random forest, +1 day") +
    theme_b40(mode) + theme(legend.position = "bottom")
  a + b + plot_layout(widths = c(1.2, 1))
}, "fig_ml_models", w = 9.4, h = 5)

save_fig(function(mode) {
  p <- PAL[[mode]]
  hb <- ml_hybrid |> filter(lead_days == 1) |>
    select(rule, `Hit rate (POD)` = POD, `Blind spot recovered` = blind_spot_recovered) |>
    pivot_longer(-rule) |> mutate(rule = factor(rule, unique(ml_hybrid$rule)))
  a <- ggplot(hb, aes(value, rule, fill = name)) +
    geom_col(position = position_dodge(0.75), width = 0.7) +
    scale_fill_manual(values = c(p$amber, p$blue), name = NULL) +
    scale_x_continuous(labels = percent, limits = c(0, 1)) +
    labs(x = NULL, y = NULL, subtitle = "Next-day alerts, 2015–2025") +
    theme_b40(mode) + theme(legend.position = "bottom")
  b <- ggplot(filter(loco, model == "Random forest"),
              aes(y = reorder(city, AUC_seen))) +
    geom_segment(aes(x = AUC_unseen, xend = AUC_seen, yend = city), colour = p$grid, linewidth = 2) +
    geom_point(aes(x = AUC_seen, colour = "Seen in training"), size = 3) +
    geom_point(aes(x = AUC_unseen, colour = "Unseen city"), size = 3) +
    scale_colour_manual(values = c(`Seen in training` = p$amber, `Unseen city` = p$blue), name = NULL) +
    labs(x = "AUC (random forest, +1 day)", y = NULL, subtitle = "Leave-one-city-out transfer") +
    theme_b40(mode) + theme(legend.position = "bottom")
  a + b + plot_layout(widths = c(1.15, 1))
}, "fig_ml_hybrid_transfer", w = 9.4, h = 5)

print(ml_skill |> mutate(across(where(is.numeric), ~ round(.x, 3))))
print(ml_hybrid |> filter(lead_days == 1) |> mutate(across(where(is.numeric), ~ round(.x, 3))))
print(loco |> group_by(model) |> summarise(across(c(AUC_seen, AUC_unseen), mean)))
message("ML models done")
