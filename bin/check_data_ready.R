# Check that the hub's latest-data.csv has been updated for the forecast date,
# i.e. that the latest target_end_date of nearly every location is the
# Saturday before the Wednesday forecast date. The hub updates data sources at
# different times (e.g. NC data can arrive hours before NSSP data), so a
# single updated location is not enough. The data is treated as updated if
# either enough locations are updated (allowing a few scattered locations to
# be missing) or only a few states have any location behind (allowing a whole
# state to be missing, e.g. Georgia). The pipeline forecasts locations that
# are behind from their last observation. NYC is excluded since its data is
# routinely a week behind.
#
# Uses the same env vars as the targets pipeline:
#   FORECAST_DATE (YYYY-MM-DD, defaults to the most recent Wednesday in ET)
#   HUB_REF       (flu-metrocast git ref, defaults to main)
# and
#   MIN_FRAC_UPDATED  (fraction of locations, excluding NYC, that must be
#                      updated, default 0.9)
#   MAX_STATES_BEHIND (number of states allowed to have any location, excluding
#                      NYC, not updated, default 2)
# The data is treated as updated if either condition is met.
#
# Exit codes:
#   0 = data is up to date for the forecast date
#   1 = data is not yet updated (too few locations updated and too many states
#       behind)
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
max_states_behind <- as.integer(Sys.getenv("MAX_STATES_BEHIND", unset = "2"))
delayed_locations <- "nyc"

if (wday(forecast_date, week_start = 1) != 3) {
  message("Forecast date ", forecast_date, " is not a Wednesday")
  quit(status = 3)
}

expected_date <- forecast_date - days(4)
hub_url <- paste0(
  "https://raw.githubusercontent.com/reichlab/flu-metrocast/", hub_ref
)
latest_data <- read.csv(paste0(hub_url, "/target-data/latest-data.csv"))
locations <- read.csv(paste0(hub_url, "/auxiliary-data/locations.csv"))
location_max <- tapply(
  ymd(latest_data$target_end_date), latest_data$location, max
)
location_max <- as.Date(location_max, origin = "1970-01-01")
max_date <- max(location_max)
checked <- location_max[!names(location_max) %in% delayed_locations]
updated <- checked >= expected_date
frac_updated <- mean(updated)
# A state is behind if any of its locations is; locations missing from the
# locations file are treated as their own state
state <- locations$state[match(names(checked), locations$location)]
state <- ifelse(is.na(state), names(checked), state)
states_behind <- unique(state[!updated])
enough_locations <- frac_updated >= min_frac_updated
few_states_behind <- length(states_behind) <= max_states_behind

message(
  "Forecast date: ", forecast_date, " | hub ref: ", hub_ref,
  " | expected max target_end_date: ", expected_date,
  " | observed: ", max_date,
  " | locations updated: ", sum(updated), "/", length(updated),
  " (excluding ", paste(delayed_locations, collapse = ", "),
  "; need ", round(100 * min_frac_updated), "%)",
  " | states behind: ", length(states_behind), "/", length(unique(state)),
  " (allowed: ", max_states_behind, ")"
)
if (any(!updated)) {
  behind <- checked[!updated]
  message(
    "Not yet updated: ",
    paste0(names(behind), " (", behind, ")", collapse = ", ")
  )
  message("States behind: ", paste(states_behind, collapse = ", "))
}

if (max_date > expected_date) {
  message("Data is newer than the forecast date; set HUB_REF to a past commit")
  quit(status = 2)
} else if (enough_locations || few_states_behind) {
  message("Data is up to date")
  quit(status = 0)
} else {
  message("Data has not been updated yet")
  quit(status = 1)
}
