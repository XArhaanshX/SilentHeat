# =============================================================================
# Beyond 40°C - interactive dashboard (R Shiny)
# Run from the project folder:   Rscript -e 'shiny::runApp("app")'
# =============================================================================

library(shiny)
library(bslib)

root <- normalizePath(if (file.exists("R/00_setup.R")) "." else "..")
Sys.setenv(B40_HOME = root)
source(file.path(root, "R", "00_setup.R"))

d       <- readRDS(path("data", "processed", "daily.rds"))
annual  <- readRDS(path("data", "processed", "annual.rds"))
gev     <- readRDS(path("outputs", "tables", "gev_fits.rds"))
ew      <- readRDS(path("outputs", "early_warning_model.rds"))
blind   <- read.csv(path("outputs", "tables", "blind_spot_by_city.csv"))
mk      <- read.csv(path("outputs", "tables", "trend_mann_kendall.csv"))
sens    <- read.csv(path("outputs", "tables", "blind_spot_sensitivity.csv"))
normals <- d |> group_by(city, doy) |>
  summarise(tmax_normal = mean(tmax_normal), .groups = "drop")
P <- PAL$dark

theme_app <- bs_theme(version = 5, bg = "#000000", fg = "#F2F2F2",
                      primary = P$amber, secondary = P$blue,
                      base_font = "Poppins, 'Segoe UI', sans-serif",
                      heading_font = "Poppins, 'Segoe UI', sans-serif")

stat_box <- function(title, value, sub = NULL, col = P$ink) {
  div(class = "p-3", style = "border:1px solid #333; border-radius:6px;",
      div(style = "color:#A8A8A8; font-size:0.85rem; text-transform:uppercase;", title),
      div(style = paste0("font-size:2.1rem; font-weight:300; color:", col, ";"), value),
      if (!is.null(sub)) div(style = "color:#A8A8A8; font-size:0.8rem;", sub))
}

ui <- page_navbar(
  title = "BEYOND 40°C",
  theme = theme_app,
  sidebar = sidebar(
    width = 260,
    selectInput("city", "City", CITIES$city, selected = "Chennai"),
    helpText("ERA5 reanalysis 1981–2025. A 'danger day' has a daily maximum wet-bulb of 29 °C or more.",
             "An 'IMD heatwave day' meets the official dry-bulb rule on 2+ consecutive days.")
  ),
  nav_panel("Blind spot",
    layout_columns(col_widths = c(3, 3, 3, 3),
      uiOutput("b1"), uiOutput("b2"), uiOutput("b3"), uiOutput("b4")),
    card(card_header("Every day since 1981: what the IMD rule saw, and what it missed"),
         plotOutput("barcode", height = "430px")),
    card(card_header("Is the miss rate sensitive to the threshold?"), tableOutput("sens"))
  ),
  nav_panel("Trends",
    card(card_header("Danger days per year, with the fitted count-model trend"),
         plotOutput("trend", height = "380px")),
    card(card_header("Mann–Kendall tests"), tableOutput("mk"))
  ),
  nav_panel("Extremes",
    layout_columns(col_widths = c(8, 4),
      card(card_header("GEV return levels of the annual maximum wet-bulb temperature"),
           plotOutput("rl", height = "420px")),
      card(card_header("Return-level calculator"),
           sliderInput("T", "Return period (years)", 2, 200, 50, step = 1),
           uiOutput("rl_txt")))
  ),
  nav_panel("Risk calculator",
    layout_columns(col_widths = c(4, 8),
      card(card_header("Today's weather"),
           dateInput("date", "Date", value = as.Date("2026-05-20")),
           numericInput("tmax", "Max temperature (°C)", 36, 20, 50, 0.1),
           numericInput("rhmin", "Min relative humidity (%)", 60, 1, 100, 1),
           numericInput("tmin", "Min temperature (°C)", 29, 10, 40, 0.1),
           numericInput("twy", "Yesterday's max wet-bulb (°C)", 28.5, 10, 35, 0.1)),
      card(card_header("Two verdicts for the same day"), uiOutput("verdict")))
  ),
  nav_panel("About",
    card(markdown(paste(
      "**Why this exists.** India's official heatwave declaration is a dry-bulb rule:",
      "40 °C on the plains or 37 °C on the coast, plus a 4.5 °C departure from normal.",
      "Humid heat limits the body's ability to cool, yet it never triggers that rule.",
      "\n\n**Methods (all in R).** Harmonic-regression normals, the IMD rule, Wilson,",
      "exact and year-block bootstrap intervals, Beta-Binomial posteriors, chi-square,",
      "McNemar and Cohen's kappa, Mann–Kendall/Sen trends, Poisson vs negative-binomial",
      "regression, GEV maximum likelihood with delta-method and bootstrap return levels,",
      "a two-state Markov chain with Monte Carlo spells, and a logistic early-warning",
      "model with Brier skill, ROC and reliability.",
      "\n\n**Data.** ERA5 via the Open-Meteo archive API (CC BY 4.0).")))
  )
)

server <- function(input, output, session) {
  cd <- reactive(d |> filter(city == input$city))
  brow <- reactive(blind |> filter(city == input$city))

  output$b1 <- renderUI(stat_box("Danger days, 1981–2025", brow()$danger_days,
                                 "daily max wet-bulb ≥ 29 °C", P$amber))
  output$b2 <- renderUI(stat_box("Missed by IMD rule",
                                 if (is.na(brow()$miss_rate)) "n/a" else percent(brow()$miss_rate, 1),
                                 if (is.na(brow()$miss_rate)) "too few danger days"
                                 else sprintf("95%% CI %s–%s", percent(brow()$boot_lo, 1),
                                              percent(brow()$boot_hi, 1)), P$amber))
  output$b3 <- renderUI(stat_box("IMD heatwave days", brow()$imd_days,
                                 paste(CITIES$imd_category[CITIES$city == input$city], "rule"),
                                 P$blue))
  output$b4 <- renderUI(stat_box("Silent danger days / year",
                                 sprintf("%.1f", brow()$silent / 45), "danger, but no heatwave"))

  output$barcode <- renderPlot({
    x <- cd() |> mutate(state = case_when(imd_heatwave & danger ~ "Both",
                                           imd_heatwave ~ "IMD heatwave",
                                           danger ~ "Silent danger",
                                           TRUE ~ NA_character_))
    ggplot(x |> filter(!is.na(state)), aes(doy, year, fill = state)) +
      geom_tile(height = 0.9, width = 1) +
      scale_fill_manual(values = c("IMD heatwave" = P$blue, "Silent danger" = P$amber,
                                   "Both" = P$ink)) +
      scale_x_continuous(limits = c(1, 366), breaks = c(1, 60, 121, 182, 244, 305),
                         labels = c("Jan", "Mar", "May", "Jul", "Sep", "Nov")) +
      scale_y_reverse(breaks = seq(1985, 2025, 5)) +
      labs(x = NULL, y = NULL) + theme_b40("dark")
  }, bg = "black", res = 110)

  output$sens <- renderTable({
    sens |> filter(city == input$city) |>
      transmute(Definition = threshold, `Flagged days` = n_days,
                `Not IMD heatwave` = missed,
                `Miss rate` = ifelse(is.na(miss_rate), "–", percent(miss_rate, 0.1)))
  }, striped = FALSE, bordered = FALSE)

  output$trend <- renderPlot({
    x <- annual |> filter(city == input$city) |> mutate(dec = (year - 2000) / 10)
    r <- mann_kendall(x$danger_days)
    fit <- if (sum(x$danger_days) >= 5)
      tryCatch(MASS::glm.nb(danger_days ~ dec, data = x),
               error = function(e) glm(danger_days ~ dec, family = poisson, data = x))
    sub <- sprintf("Mann–Kendall p = %s · Sen slope %+.2f days/decade", fmt_p(r$p_value),
                   10 * r$sen_slope)
    if (!is.null(fit)) sub <- paste0(sub, sprintf(" · negative-binomial trend ×%.2f per decade",
                                                  exp(coef(fit)[2])))
    g <- ggplot(x, aes(year, danger_days)) +
      geom_col(fill = P$amber, width = 0.8)
    if (!is.null(fit)) g <- g + geom_line(aes(y = fitted(fit)), colour = P$ink, linewidth = 0.8)
    g + labs(x = NULL, y = "Danger days", subtitle = sub) +
      theme_b40("dark")
  }, bg = "black", res = 110)

  output$mk <- renderTable({
    mk |> filter(city == input$city) |>
      transmute(Indicator = indicator, S, Z = round(Z, 2), `p-value` = fmt_p(p_value),
                `Kendall tau` = round(tau, 3), `Sen slope / decade` = round(sen_per_decade, 3))
  })

  output$rl <- renderPlot({
    g <- gev[[input$city]]; f <- g$st
    T <- exp(seq(log(1.05), log(200), length.out = 120))
    cur <- do.call(rbind, lapply(T, function(tt) gev_return_level(f, tt)))
    z <- sort(g$z); n <- length(z)
    emp <- data.frame(T = 1 / (1 - (1:n) / (n + 1)), level = z)
    ggplot(cur, aes(T, level)) +
      geom_ribbon(aes(ymin = level - 1.96 * se, ymax = level + 1.96 * se),
                  fill = P$amber, alpha = 0.25) +
      geom_line(colour = P$amber, linewidth = 1) +
      geom_point(data = emp, colour = P$ink, size = 1.8) +
      geom_vline(xintercept = input$T, colour = P$blue, linetype = "22") +
      scale_x_log10(breaks = c(2, 5, 10, 25, 50, 100, 200)) +
      labs(x = "Return period (years)", y = "Annual max wet-bulb (°C)") +
      theme_b40("dark")
  }, bg = "black", res = 110)

  output$rl_txt <- renderUI({
    g <- gev[[input$city]]; r <- gev_return_level(g$st, input$T); pr <- g$params
    tagList(
      stat_box(paste0(input$T, "-year return level"), sprintf("%.2f °C", r$level),
               sprintf("95%% CI %.2f–%.2f °C", r$level - 1.96 * r$se, r$level + 1.96 * r$se),
               P$amber),
      br(),
      p(sprintf("Shape ξ = %.2f (SE %.2f). Location trend %+.2f °C/decade (LRT p = %s).",
                pr$xi, pr$xi_se, pr$ns_mu1_per_decade, fmt_p(pr$trend_p))),
      p(sprintf("Chance of at least one 31 °C day in 2026–2035 under the trend: %s.",
                percent(pr$p_critical_any_2026_35_trend, 0.1))))
  })

  output$verdict <- renderUI({
    cn <- input$city; doy <- as.integer(format(input$date, "%j"))
    cat <- CITIES$imd_category[CITIES$city == cn]
    nrm <- normals$tmax_normal[normals$city == cn & normals$doy == doy]
    dep <- input$tmax - nrm
    imd_ok <- if (cat == "Plains") (input$tmax >= 40 & dep >= 4.5) | input$tmax >= 45
              else input$tmax >= 37 & dep >= 4.5
    off <- ew$stull_offset$offset[ew$stull_offset$city == cn]
    tw <- stull_wetbulb(input$tmax, input$rhmin) + off
    hi <- heat_index(input$tmax, input$rhmin)
    prob <- if (cn %in% ew$cities) {
      w <- 2 * pi * doy / 365.25
      nd <- data.frame(city = factor(cn, levels = ew$model$xlevels$city),
                       twmax = tw, tw_change = tw - input$twy, tmax = input$tmax,
                       rhmin = input$rhmin, tmin = input$tmin, year_c = (2026 - 2000) / 10,
                       s1 = sin(w), c1 = cos(w), s2 = sin(2 * w), c2 = cos(2 * w))
      predict(ew$model, nd, type = "response")
    } else NA
    tagList(
      layout_columns(col_widths = c(6, 6),
        stat_box("IMD heatwave rule", if (imd_ok) "QUALIFIES" else "NO ALERT",
                 sprintf("%s rule · departure %+.1f °C from a %.1f °C normal", cat, dep, nrm),
                 if (imd_ok) P$blue else P$muted),
        stat_box("Humid-heat physiology", sprintf("Tw ≈ %.1f °C", tw),
                 if (tw >= TW_CRITICAL) "CRITICAL (≥ 31 °C)"
                 else if (tw >= TW_DANGER) "DANGER (≥ 29 °C)" else "below danger threshold",
                 if (tw >= TW_DANGER) P$amber else P$muted)),
      br(),
      layout_columns(col_widths = c(6, 6),
        stat_box("P(danger day tomorrow)",
                 if (is.na(prob)) "n/a" else percent(prob, 0.1),
                 if (is.na(prob)) "humid danger is historically absent here"
                 else sprintf("logistic model · warn above %.0f%%", 100 * ew$threshold),
                 if (!is.na(prob) && prob >= ew$threshold) P$amber else P$ink),
        stat_box("IMD experimental Heat Index", sprintf("%.0f °C", hi),
                 paste(as.character(hi_band(hi)), "band"), P$ink)))
  })
}

shinyApp(ui, server)
