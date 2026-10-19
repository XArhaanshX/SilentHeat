# =============================================================================
# run_all.R  -  reproduce the entire Beyond 40°C study with one command:
#     Rscript run_all.R            (from the project folder)
# Steps: download -> features -> EDA -> distributions -> blind spot ->
#        trends -> extremes -> Markov spells -> early warning -> ML models -> report
# =============================================================================

Sys.setenv(B40_HOME = normalizePath("."))
source("R/00_setup.R")

steps <- c("01_fetch_data.R", "02_build_features.R", "03_eda.R",
           "04_distribution_fit.R", "05_blind_spot.R", "06_trends.R",
           "07_extremes_gev.R", "08_markov_spells.R", "09_early_warning.R", "11_ml_models.R",
           "10_render_report.R")

t_all <- Sys.time()
for (s in steps) {
  t0 <- Sys.time()
  message("\n========== ", s, " ==========")
  source(file.path("R", s), local = new.env(parent = globalenv()))
  message(sprintf("   finished in %.1f s", as.numeric(Sys.time() - t0, units = "secs")))
}
message(sprintf("\nAll steps done in %.1f min. Outputs in outputs/, report in report/.",
                as.numeric(Sys.time() - t_all, units = "mins")))
message("Launch the dashboard with:  Rscript -e 'shiny::runApp(\"app\")'")
