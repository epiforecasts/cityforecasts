# Check that the hub's latest-data.csv has been updated for the forecast date,
# i.e. that max(target_end_date) is the Saturday before the Wednesday
# forecast date.
#
# Uses the same env vars as the targets pipeline:
#   FORECAST_DATE (YYYY-MM-DD, defaults to the most recent Wednesday in ET)
#   HUB_REF       (flu-metrocast git ref, defaults to main)
#
# Exit codes:
#   0 = data is up to date for the forecast date
#   1 = data is not yet updated (latest date is before the expected Saturday)
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
max_date <- max(ymd(latest_data$target_end_date))

message(
  "Forecast date: ", forecast_date, " | hub ref: ", hub_ref,
  " | expected max target_end_date: ", expected_date,
  " | observed: ", max_date
)

if (max_date == expected_date) {
  message("Data is up to date")
  quit(status = 0)
} else if (max_date < expected_date) {
  message("Data has not been updated yet")
  quit(status = 1)
} else {
  message("Data is newer than the forecast date; set HUB_REF to a past commit")
  quit(status = 2)
}
