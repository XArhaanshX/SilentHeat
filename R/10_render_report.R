# =============================================================================
# 10_render_report.R  -  knit report/report.Rmd to a self-contained HTML file
# (knitr + markdown, no pandoc needed) and print it to PDF with headless Chrome
# =============================================================================

old <- setwd(path("report"))

knitr::knit("report.Rmd", "report.md", quiet = TRUE, envir = new.env())
markdown::mark_html("report.md", output = "report.html",
                    meta = list(css = c("default", "report.css")),
                    options = "+toc-smartypants")
message("HTML report: report/report.html")

chrome <- Sys.which(c("google-chrome-stable", "google-chrome", "chromium", "chromium-browser"))
chrome <- chrome[nzchar(chrome)][1]
if (!is.na(chrome)) {
  system2(chrome, c("--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    "--virtual-time-budget=15000", "--print-to-pdf=report.pdf",
                    paste0("file://", normalizePath("report.html"))),
          stdout = FALSE, stderr = FALSE)
  if (file.exists("report.pdf")) message("PDF report: report/report.pdf")
} else {
  message("Chrome not found - open report.html and print to PDF manually.")
}
setwd(old)
