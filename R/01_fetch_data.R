# =============================================================================
# 01_fetch_data.R  -  download 45 years of daily ERA5 reanalysis per city
# Source: Open-Meteo historical weather API (ERA5 / ERA5-Land, CC BY 4.0)
# =============================================================================

library(jsonlite)

VARS <- c(tmax = "temperature_2m_max",
          tmin = "temperature_2m_min",
          twmax = "wet_bulb_temperature_2m_max",
          twmean = "wet_bulb_temperature_2m_mean",
          rhmin = "relative_humidity_2m_min",
          rhmean = "relative_humidity_2m_mean")

build_url <- function(lat, lon, start, end) {
  paste0("https://archive-api.open-meteo.com/v1/archive?",
         "latitude=", lat, "&longitude=", lon,
         "&start_date=", start, "&end_date=", end,
         "&daily=", paste(VARS, collapse = ","),
         "&timezone=Asia%2FKolkata")
}

fetch_city <- function(row, max_tries = 6) {
  out <- path("data", "raw", paste0(row$city, ".csv"))
  if (file.exists(out)) {
    message("  cached  ", row$city)
    return(read.csv(out))
  }
  url <- build_url(row$lat, row$lon, START_DATE, END_DATE)
  for (attempt in seq_len(max_tries)) {
    res <- tryCatch(fromJSON(url), error = function(e) e)
    if (!inherits(res, "error") && !is.null(res$daily)) break
    wait <- 30 * attempt              # API rate limits: back off and retry
    message("  retry ", attempt, " for ", row$city, " in ", wait, "s: ",
            conditionMessage(res))
    Sys.sleep(wait)
  }
  if (inherits(res, "error")) stop("Download failed for ", row$city)
  d <- as.data.frame(res$daily)
  names(d) <- c("date", names(VARS)[match(names(d)[-1], VARS)])
  d$city <- row$city
  d$grid_lat <- res$latitude; d$grid_lon <- res$longitude
  d$elevation <- res$elevation
  write.csv(d, out, row.names = FALSE)
  message("  fetched ", row$city, " (", nrow(d), " days)")
  Sys.sleep(15)                       # stay well under the per-minute quota
  d
}

message("Fetching ", nrow(CITIES), " cities, ", START_DATE, " to ", END_DATE)
raw <- do.call(rbind, lapply(split(CITIES, seq_len(nrow(CITIES))), fetch_city))
raw$date <- as.Date(raw$date)
saveRDS(raw, path("data", "processed", "daily_raw.rds"))

# Data-quality report: completeness per city and variable
dq <- raw |>
  group_by(city) |>
  summarise(days = n(), first = min(date), last = max(date),
            across(all_of(names(VARS)), ~ mean(is.na(.x)) * 100, .names = "pct_na_{.col}"),
            grid_lat = first(grid_lat), grid_lon = first(grid_lon),
            elevation_m = first(elevation), .groups = "drop")
save_table(dq, "data_quality")
print(dq)
