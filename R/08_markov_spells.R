# =============================================================================
# 08_markov_spells.R  -  RQ4: do dangerous days cluster into spells?
#   Two-state Markov chain (calm / danger) within each city's peak humid
#   season, test of first-order dependence, geometric spell-length law,
#   and Monte Carlo comparison of the 1981-2000 and 2006-2025 climates.
# =============================================================================

set.seed(2026)   # reproducible bootstrap / permutation / Monte Carlo draws
d <- readRDS(path("data", "processed", "daily.rds"))
N_SIM <- 10000
MIN_DANGER <- 50

# Peak season per city: 61 days centred on the calendar day where the
# (circularly smoothed) probability of a danger day is highest
peak_window <- function(x) {
  p <- tapply(x$danger, factor(x$doy, levels = 1:366), mean)
  p[is.na(p)] <- 0
  k <- 15; ext <- c(tail(p, k), p, head(p, k))
  sm <- stats::filter(ext, rep(1 / (2 * k + 1), 2 * k + 1), sides = 2)[(k + 1):(k + 366)]
  centre <- which.max(sm)
  ((centre - 31):(centre + 29) - 1) %% 366 + 1
}

chain_from <- function(x) {
  tab <- markov_counts(x$danger, x$year)
  p01 <- tab["calm", "danger"] / sum(tab["calm", ])
  p11 <- tab["danger", "danger"] / sum(tab["danger", ])
  list(tab = tab, p01 = p01, p11 = p11)
}

simulate_season <- function(n_days, p01, p11) {
  pi1 <- p01 / (p01 + 1 - p11)
  s <- logical(n_days); s[1] <- runif(1) < pi1
  u <- runif(n_days)
  for (i in 2:n_days) s[i] <- u[i] < if (s[i - 1]) p11 else p01
  s
}

eligible <- d |> group_by(city) |> summarise(n = sum(danger)) |>
  filter(n >= MIN_DANGER) |> pull(city)

mk_rows <- list(); spell_rows <- list(); sim_rows <- list(); windows <- list()
for (cn in eligible) {
  x <- d |> filter(city == cn)
  win <- peak_window(x); windows[[cn]] <- range(as.Date(win - 1, origin = "2001-01-01"))
  xs <- x |> filter(doy %in% win) |> arrange(date)
  ch <- chain_from(xs)

  # H0: tomorrow's state is independent of today's (i.e. p11 = p01)
  chi <- suppressWarnings(chisq.test(ch$tab, correct = FALSE))
  E <- chi$expected; O <- ch$tab
  G2 <- 2 * sum(ifelse(O > 0, O * log(O / E), 0))

  # Spell lengths vs the geometric law implied by the chain
  sp <- unlist(lapply(split(xs$danger, xs$year), spell_lengths))
  bins <- c(1:4, Inf)
  obs_b <- table(cut(sp, c(0, 1, 2, 3, 4, Inf)))
  pk <- c(sapply(1:4, function(k) ch$p11^(k - 1) * (1 - ch$p11)), ch$p11^4)
  gof <- suppressWarnings(chisq.test(as.numeric(obs_b), p = pk))

  pi1 <- ch$p01 / (ch$p01 + 1 - ch$p11)
  mk_rows[[cn]] <- data.frame(
    city = cn, peak_from = format(windows[[cn]][1], "%d %b"),
    peak_to = format(windows[[cn]][2], "%d %b"),
    p01 = ch$p01, p11 = ch$p11, p10 = 1 - ch$p11,
    stationary_pi = pi1, observed_freq = mean(xs$danger),
    chi_sq = unname(chi$statistic), chi_p = chi$p.value, G2 = G2,
    G2_p = pchisq(G2, 1, lower.tail = FALSE),
    odds_ratio_persistence = (O[2, 2] * O[1, 1]) / (O[2, 1] * O[1, 2]),
    n_spells = length(sp), mean_spell_obs = mean(sp),
    mean_spell_geom = 1 / (1 - ch$p11), longest_spell = max(sp),
    geom_gof_chisq = unname(gof$statistic), geom_gof_p = gof$p.value)
  spell_rows[[cn]] <- data.frame(city = cn, length = c("1", "2", "3", "4", "5+"),
                                 observed = as.numeric(obs_b),
                                 expected = length(sp) * pk)

  # Monte Carlo: same 61-day season under each era's estimated chain
  for (era in c("1981–2000", "2006–2025")) {
    xe <- if (era == "1981–2000") xs |> filter(year <= 2000) else xs |> filter(year >= 2006)
    ce <- chain_from(xe)
    sims <- replicate(N_SIM, {
      s <- simulate_season(length(win), ce$p01, ce$p11)
      sl <- spell_lengths(s)
      c(days = sum(s), longest = if (length(sl)) max(sl) else 0)
    })
    sim_rows[[paste(cn, era)]] <- data.frame(
      city = cn, era = era, p01 = ce$p01, p11 = ce$p11,
      mean_days = mean(sims["days", ]),
      obs_mean_days = mean(tapply(xe$danger, xe$year, sum)),
      p_longest_ge3 = mean(sims["longest", ] >= 3),
      p_longest_ge5 = mean(sims["longest", ] >= 5),
      p_longest_ge7 = mean(sims["longest", ] >= 7))
  }
}
markov <- bind_rows(mk_rows); spells <- bind_rows(spell_rows); sims <- bind_rows(sim_rows)
save_table(markov, "markov_chain")
save_table(spells, "markov_spell_lengths")
save_table(sims, "markov_monte_carlo")

# ---- Figures ---------------------------------------------------------------
save_fig(function(mode) {
  p <- PAL[[mode]]
  x <- spells |> mutate(city = factor(city, CITIES$city))
  ggplot(x, aes(length)) +
    geom_col(aes(y = observed), fill = p$amber, width = 0.7) +
    geom_point(aes(y = expected), colour = p$ink, size = 2.4) +
    geom_line(aes(y = expected, group = 1), colour = p$ink, linewidth = 0.5) +
    facet_wrap(~city, nrow = 1, scales = "free_y") +
    labs(x = "Spell length (consecutive danger days)", y = "Number of spells",
         caption = "Bars = observed spells in each city's 61-day peak season; dots = geometric law implied by the fitted Markov chain.") +
    theme_b40(mode, base = 12)
}, "fig_spell_lengths", w = 12, h = 4.4)

save_fig(function(mode) {
  p <- PAL[[mode]]
  x <- sims |>
    dplyr::select(city, era, p_longest_ge3, p_longest_ge5) |>
    pivot_longer(c(p_longest_ge3, p_longest_ge5), names_to = "event", values_to = "prob") |>
    mutate(event = factor(event, c("p_longest_ge3", "p_longest_ge5"),
                          c("≥ 3-day spell in a season", "≥ 5-day spell in a season")),
           city = factor(city, rev(CITIES$city)))
  ggplot(x, aes(prob, city, colour = era)) +
    geom_line(aes(group = city), colour = p$muted, linewidth = 0.6) +
    geom_point(size = 3.2) +
    facet_wrap(~event) +
    scale_x_continuous(labels = percent) +
    scale_colour_manual(values = c("1981–2000" = p$blue, "2006–2025" = p$amber)) +
    labs(x = "Monte Carlo probability\n(10,000 simulated seasons per era)", y = NULL) +
    theme_b40(mode)
}, "fig_markov_montecarlo", w = 7, h = 5)

message("Markov analysis done")
