# Check that the hub's latest-data.csv has been updated for the forecast date,
# i.e. that nearly every location's latest target_end_date is the Saturday
# before the Wednesday forecast date. The hub updates data sources at
# different times (e.g. NC data can arrive hours before NSSP data), so a
# single updated location is not enough. NYC is excluded since its data is
# routinely a week behind.
#
# Uses the same env vars as the targets pipeline:
#   FORECAST_DATE (YYYY-MM-DD, defaults to the most recent Wednesday in ET)
#   HUB_REF       (flu-metrocast git ref, defaults to main)
# and
#   MIN_FRAC_UPDATED (fraction of locations, excluding NYC, that must be
#                     updated, default 0.9)
#
# Exit codes:
#   0 = data is up to date for the forecast date
#   1 = data is not yet updated (too few locations have the expected Saturday)
#   2 = data is newer than expected (e.g. a past FORECAST_DATE without HUB_REF)
#   3 = forecast date is not a Wednesday

suppressPackageStartupMessages(library(lubridate))

forecast_date <- ymd(Sys.getenv(
  "FORECAST_DATE",
  unset = as.character(floor_date(
    today(tzone = "America/New_York"), "week",
    week_start = 3
  ))
))
hub_ref <- Sys.getenv("HUB_REF", unset = "main")
min_frac_updated <- as.numeric(Sys.getenv("MIN_FRAC_UPDATED", unset = "0.9"))
delayed_locations <- "nyc"

if (wday(forecast_date, week_start = 1) != 3) {
  message("Forecast date ", forecast_date, " is not a Wednesday")
  quit(status = 3)
}

expected_date <- forecast_date - days(4)
latest_data_url <- paste0(
  "https://raw.githubusercontent.com/reichlab/flu-metrocast/", hub_ref,
  "/target-data/latest-data.csv"
)
latest_data <- read.csv(latest_data_url)
location_max <- tapply(
  ymd(latest_data$target_end_date), latest_data$location, max
)
location_max <- as.Date(location_max, origin = "1970-01-01")
max_date <- max(location_max)
checked <- location_max[!names(location_max) %in% delayed_locations]
updated <- checked >= expected_date
frac_updated <- mean(updated)

message(
  "Forecast date: ", forecast_date, " | hub ref: ", hub_ref,
  " | expected max target_end_date: ", expected_date,
  " | observed: ", max_date,
  " | locations updated: ", sum(updated), "/", length(updated),
  " (excluding ", paste(delayed_locations, collapse = ", "),
  "; need ", round(100 * min_frac_updated), "%)"
)
if (any(!updated)) {
  behind <- checked[!updated]
  message(
    "Not yet updated: ",
    paste0(names(behind), " (", behind, ")", collapse = ", ")
  )
}

if (max_date > expected_date) {
  message("Data is newer than the forecast date; set HUB_REF to a past commit")
  quit(status = 2)
} else if (frac_updated >= min_frac_updated) {
  message("Data is up to date")
  quit(status = 0)
} else {
  message("Data has not been updated yet")
  quit(status = 1)
}
