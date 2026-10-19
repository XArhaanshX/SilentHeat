# =============================================================================
# install.R  -  install every R package the pipeline, report and app need:
#     Rscript install.R
# =============================================================================

pkgs <- c("dplyr", "tidyr", "ggplot2", "scales", "patchwork", "ggridges",   # data + figures
          "jsonlite",                                                      # ERA5 download
          "fitdistrplus", "MASS", "evd", "pROC",                           # statistics
          "rpart", "ranger",                                               # ML models
          "knitr", "markdown",                                             # report
          "shiny", "bslib")                                                # dashboard

missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All ", length(pkgs), " packages already installed.")
}
