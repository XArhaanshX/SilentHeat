# =============================================================================
# 02_build_features.R  -  climatological normals, the IMD heatwave rule,
# humid-heat flags and the heat index
# =============================================================================

raw <- readRDS(path("data", "processed", "daily_raw.rds"))

d <- raw |>
  left_join(CITIES[, c("city", "imd_category")], by = "city") |>
  arrange(city, date) |>
  mutate(year  = as.integer(format(date, "%Y")),
         month = as.integer(format(date, "%m")),
         doy   = as.integer(format(date, "%j")),
         season = case_when(month %in% 3:5  ~ "Pre-monsoon (MAM)",
                            month %in% 6:9  ~ "Monsoon (JJAS)",
                            month %in% 10:12 ~ "Post-monsoon (OND)",
                            TRUE ~ "Winter (JF)"))

# ---- 1. Daily climatological normal via harmonic (Fourier) regression -------
# IMD judges a heatwave by the departure from the station's normal for that
# calendar day. We estimate the normal over the WMO 1991-2020 base period with
# a 3-harmonic linear model  Tmax = b0 + sum_k [a_k sin(2*pi*k*doy/365.25) + b_k cos(...)]
harmonics <- function(doy, K = 3) {
  w <- 2 * pi * doy / 365.25
  m <- sapply(1:K, function(k) cbind(sin(k * w), cos(k * w)))
  m <- matrix(m, ncol = 2 * K)
  colnames(m) <- paste0(rep(c("s", "c"), K), rep(1:K, each = 2))
  m
}

normal_fits <- lapply(split(d, d$city), function(x) {
  base <- x[x$year >= 1991 & x$year <= 2020, ]
  H <- harmonics(base$doy)
  list(tmax = lm(base$tmax ~ H), tmin = lm(base$tmin ~ H))
})
normal_stats <- do.call(rbind, lapply(names(normal_fits), function(cn) {
  s <- summary(normal_fits[[cn]]$tmax)
  data.frame(city = cn, r_squared = s$r.squared, resid_sd = s$sigma,
             F_stat = unname(s$fstatistic[1]),
             p_value = pf(s$fstatistic[1], s$fstatistic[2], s$fstatistic[3],
                          lower.tail = FALSE))
}))
save_table(normal_stats, "normal_model_fit")

d <- d |>
  group_by(city) |>
  mutate(
    tmax_normal = drop(cbind(1, harmonics(doy)) %*% coef(normal_fits[[first(city)]]$tmax)),
    tmin_normal = drop(cbind(1, harmonics(doy)) %*% coef(normal_fits[[first(city)]]$tmin)),
    departure   = tmax - tmax_normal
  ) |>
  ungroup()

# ---- 2. The official IMD heatwave rule ---------------------------------------
# Plains : Tmax >= 40 and departure >= 4.5, or Tmax >= 45 outright
# Coastal: Tmax >= 37 and departure >= 4.5
# Severe : departure > 6.4 (or Tmax >= 47 on the plains)
# Declared when met on >= 2 consecutive days. We use one grid cell instead of
# two stations, which makes our rule *more* generous to IMD, so every miss rate
# reported below is a conservative (lower-bound) estimate.
d <- d |>
  mutate(
    imd_qualify = if_else(imd_category == "Plains",
                          (tmax >= 40 & departure >= 4.5) | tmax >= 45,
                          tmax >= 37 & departure >= 4.5),
    imd_severe_qualify = if_else(imd_category == "Plains",
                                 (tmax >= 40 & departure > 6.4) | tmax >= 47,
                                 tmax >= 37 & departure > 6.4)
  ) |>
  group_by(city) |>
  mutate(imd_heatwave = run_length_of(imd_qualify) >= 2,
         imd_severe   = imd_heatwave & imd_severe_qualify) |>
  ungroup()

# ---- 3. Humid-heat flags and the heat index ----------------------------------
d <- d |>
  mutate(
    danger   = twmax >= TW_DANGER,
    critical = twmax >= TW_CRITICAL,
    silent_danger = danger & !imd_heatwave,          # the blind spot
    heat_index = heat_index(tmax, rhmin),            # RH minimum ~ time of Tmax
    hi_band  = hi_band(heat_index),
    tw_stull = stull_wetbulb(tmax, rhmin)            # independent physics check
  )

# Validation: Stull wet-bulb at (Tmax, RHmin) should track ERA5 daily max Tw
val <- d |>
  group_by(city) |>
  summarise(r = cor(tw_stull, twmax, use = "complete.obs"),
            mean_diff = mean(twmax - tw_stull, na.rm = TRUE), .groups = "drop")
save_table(val, "wetbulb_validation")

saveRDS(d, path("data", "processed", "daily.rds"))
message("Feature table: ", nrow(d), " city-days, ",
        sum(d$danger, na.rm = TRUE), " danger days, ",
        sum(d$imd_heatwave, na.rm = TRUE), " IMD heatwave days")
