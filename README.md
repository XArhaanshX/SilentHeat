# Beyond 40 °C

**Quantifying the humid-heat blind spot in India's heatwave warnings**
Probability & Statistics Lab project, built end-to-end in R.

## The gap

India declares a heatwave only on **dry-bulb** temperature: 40 °C on the plains or 37 °C on the coast, plus a 4.5 °C departure from normal. That declaration triggers Heat Action Plans. Humid heat, which is what actually stops the body cooling, is not part of the rule. A 2023 Centre for Policy Research review of 37 plans found that most use national thresholds and ignore humid heat. Lab physiology (Vecellio et al., 2022) puts the humid-air limit for healthy young adults at a wet-bulb of about 30–31 °C.

**Question:** how much dangerous humid heat does the official rule miss? Is the miss growing, and can probability models close it?

## Headline results (10 cities, 1981–2025, 164,360 city-days)

| Research question | Result |
|---|---|
| RQ1 Blind spot | **96.3%** of dangerous humid-heat days (wet-bulb ≥ 29 °C) were *not* IMD heatwave days (703/730, Wilson 95% CI 94.7–97.4%). Cohen's κ ≈ 0. Same in every city; 96–99% under every threshold tested. |
| RQ2 Trend | Danger days grow **×1.54 per decade** (negative binomial, 95% CI 1.34–1.77). April–June wet-bulb in 2021–25 is 0.53 °C above 1981–90. |
| RQ3 Extremes | Location shift of the GEV is significant in 7/10 cities. Chennai's 1-in-50-year extreme of 1985 is now **1-in-2.6 years**. |
| RQ4 Spells | Strong day-to-day persistence (odds ratio 27–41) with geometric spell lengths. In Chennai, P(≥ 3-day spell per season) rose from 2% to 23%. |
| RQ5 Warning | A logistic next-day model reaches **AUC 0.92** (vs 0.61 for the IMD-rule state), with Brier skill +17% over climatology. |
| RQ6 ML | Baseline ML (decision tree, random forest) 1–3 days ahead. Random forest: **AUC 0.95** at +1 day, 0.89 at +3. A hybrid IMD + RF alert recovers **45%** of the blind spot (IMD alone: 1%). Leave-one-city-out AUC 0.93 vs 0.94 in-city, so it transfers to cities with no history. |

## Run it

```bash
Rscript run_all.R                     # download → features → 7 analyses → figures → report (~1 min)
Rscript -e 'shiny::runApp("app")'     # interactive dashboard
uv run --with python-pptx --with pillow python presentation/build_deck.py   # rebuild the slides
```

Needs R ≥ 4.3 with: dplyr, tidyr, ggplot2, scales, patchwork, ggridges, jsonlite, fitdistrplus, MASS, evd, pROC, rpart, ranger, shiny, bslib, knitr, markdown. The raw downloads are cached in `data/raw/`, so later runs work offline.

## Layout

```
R/00_setup.R            shared helpers, written from scratch: GEV likelihood/MLE/return levels,
                        Mann–Kendall + Sen, Wilson CI, Cohen's κ, Markov counts, Stull wet-bulb, NWS heat index
R/01_fetch_data.R       ERA5 via Open-Meteo API (jsonlite, retries, cache)
R/02_build_features.R   harmonic-regression normals, IMD heatwave rule, humid-heat flags, heat index
R/03_eda.R              descriptive stats, Tmax–RH correlation, wet-bulb regression, figures
R/04_distribution_fit.R Normal/Gamma/Weibull/Lognormal MLE; Poisson vs negative binomial
R/05_blind_spot.R       RQ1: miss rates with Wilson/exact/block-bootstrap/Bayes intervals, χ², McNemar, κ, sensitivity
R/06_trends.R           RQ2: Mann–Kendall, NB GLM, era tests (Wilcoxon, Welch, KS, permutation), ANOVA + Tukey, Friedman
R/07_extremes_gev.R     RQ3: GEV MLE (checked against evd::fgev), return levels, non-stationary GEV + LRT
R/08_markov_spells.R    RQ4: two-state Markov chain, geometric spells, Monte Carlo by era
R/09_early_warning.R    RQ5: logistic model, Brier skill, ROC/DeLong, reliability, operating points
R/11_ml_models.R        RQ6: logistic / decision tree / random forest at 1-3 day leads, physiology-informed
                        headroom features, hybrid IMD + ML alert, leave-one-city-out transfer
R/10_render_report.R    knitr + markdown → report/report.html → report.pdf (headless Chrome)
app/app.R               Shiny dashboard (blind spot · trends · extremes · risk calculator · about)
report/report.Rmd       the written report; every number is pulled live from outputs/
presentation/           Beyond40C_ProbStats.pptx (+ .pdf) and its builder; styled after the fatigue-detection deck
outputs/tables/         30+ CSV/RDS result tables
outputs/figures/        each figure twice: deck/ (dark, transparent) and report/ (light)
```

## Notes and limitations

- ERA5 (0.25°) smooths local peaks, so station data would raise every count. The dry-vs-humid separation is structural.
- We apply the IMD rule to one grid cell, not two stations. That is more generous to IMD, so the miss rates are lower bounds.
- The deck uses the Poppins font (free on Google Fonts). Install it on the presenting machine, or present the PDF copy.

Data: ERA5 (Hersbach et al., 2020) via Open-Meteo, CC BY 4.0.
