#### R script to pre-process forecasting data from a config #####
library(argparser, quietly = TRUE)
library(RcppTOML)
library(dplyr)
library(lubridate)
library(tidyr)
library(ggplot2)



# Command Line Version --------------------------------------------------------
parsed_args <- arg_parser("Preprocess the data for a config") |>
  add_argument("config", help = "Path to TOML config file") |>
  add_argument("config_index",
    help = "index of entry in config to use",
    type = "integer"
  ) |>
  parse_args()

if (!is.na(parsed_args$config)) {
  # config <- parseTOML("input/example_config_weekly.toml") #nolint
  config <- parseTOML(parsed_args$config)
  index <- parsed_args$config_index
} else {
  message("File specified in config filepath does not exist")
}


# Use the config file to preprocess the data for the first index
# Will want to put these in functions but for now just do everything
# in a script

raw_data_all <- read.csv(config$data_url[index])
# hardcoding this in for now bc can't get filtering from variables to work
# see below

# this_raw_data <- raw_data |>
#   filter(location %in%
#     config$locs_list[[{{config$regions_to_fit[index]}}]])\

if (config$regions_to_fit[index] == "NYC") {
  raw_data <- filter(
    raw_data_all,
    location %in%
      c(
        "Bronx", "Brooklyn", "Manhattan", "NYC",
        "Queens", "Staten Island", "Unknown"
      )
  )
} else if (config$regions_to_fit[index] == "TX") {
  raw_data <- filter(
    raw_data_all,
    location %in%
      c(
        "San Antonio", "Dallas", "El Paso",
        "Houston", "Austin"
      )
  )
}

# Set up filepaths for saving data and figs -------------------------------
fp_figs <- file.path(
  "output",
  "figures",
  config$forecast_date,
  config$data_filename[index]
)
model_data_filename <- config$data_filename[index]
fp_data <- file.path(
  config$input_data_path,
  config$forecast_date
)
fs::dir_create(fp_figs, recurse = TRUE)
fs::dir_create(fp_data, recurse = TRUE)


# Pre-processing: NYC daily count data ----------------------------------------
if (isTRUE(config$data_format_type[index] == "NYC_ED_daily_asof") && config$targets[index] == "ILI ED visits") { # nolint

  # Recent data
  data_formatted <- raw_data |>
    mutate(
      date = as.Date(Date, format = "%m/%d/%Y") + years(2000),
      obs_data = as.integer(X),
      # Eventually we will want to scale these (compute z scores) but leave
      # as is for now
      year = year(date),
      week = week(date),
      day_of_week = wday(date)
    ) |>
    filter(Dim2Value == "All age groups") |>
    rename(location = Dim1Value) |>
    select(date, count, location, year, week, day_of_week)

  # Preprocessing: weekly data ---------------------------------------------
} else {
  # Formatting for weekly target data
  data_formatted <- raw_data |>
    mutate(
      date = ymd(target_end_date),
      obs_data = observation,
      year = year(date),
      week = week(date),
      day_of_week = wday(date)
    ) |>
    filter(
      as_of == config$forecast_date,
      date < config$forecast_date
    ) |>
    arrange(date) |>
    select(date, obs_data, location, year, week, day_of_week)
}

# Handle Unknown/NYC category
if (config$regions_to_fit[index] == "NYC" && !"Unknown" %in% unique(data_formatted$location)) { # nolint
  # Then we need to create "Unknown" from NYC - sum(boroughs)
  intermediate <- data_formatted |>
    group_by(date) |>
    mutate(loc = ifelse(location == "NYC", "NYC", "borough")) |>
    group_by(date, loc) |>
    summarise(obs_data = sum(obs_data)) |>
    tidyr::pivot_wider(
      id_cols = "date",
      names_from = "loc",
      values_from = "obs_data"
    ) |>
    ungroup() |>
    mutate(Unknown = NYC - borough) |>
    select(date, Unknown) |>
    rename(obs_data = Unknown) |>
    mutate(
      location = "Unknown",
      year = year(date),
      week = week(date),
      day_of_week = wday(date)
    ) |>
    select(date, obs_data, location, year, week, day_of_week)

  data_formatted <- bind_rows(data_formatted, intermediate) |>
    arrange(date) |>
    filter(!location %in% c("NYC", "Citywide"))
} else if (config$regions_to_fit[index] == "NYC" && "Unknown" %in% unique(data_formatted$location)) { # nolint
  # Then we just need to exclude NYC
  data_formatted <- data_formatted |>
    filter(!location %in% c("NYC", "Citywide"))
}



if (isTRUE(config$exclude_COVID[index])) {
  n_orig <- nrow(data_formatted)
  data_formatted <- data_formatted |>
    filter(!date %in% seq(
      from = ymd(config$data_exclusion_period[1]),
      to = ymd(config$data_exclusion_period[2]),
      by = "day"
    ))
  n_new <- nrow(data_formatted)
  if (n_new < n_orig) {
    message("Training data has been filtered to exclude COVID years")
  }
}


# Model data: daily count data------------------------------------------------
if (config$targets[index] == "ILI ED visits" && config$regions_to_fit[index] == "NYC" && config$timestep_data[index] == "day") { # nolint
  model_data <- data_formatted |>
    mutate(series = as.factor(location)) |>
    group_by(series, location) |>
    tidyr::complete(date = seq(min(date), max(date), by = "day")) |>
    ungroup() |>
    # Remake the predictors to fill in the missing ones
    mutate(
      year = year(date),
      week = week(date),
      day_of_week = wday(date)
    ) |>
    mutate(
      year = year - min(year) + 1,
      time = as.integer(date - min(date) + 1),
      season = ifelse(week <= 31, year, year + 1)
    ) |>
    select(time, date, count, series, location, year, season, week, day_of_week)

  # Create daily forecast data to pass into mvgam
  next_saturday <- ymd(config$forecast_date) + (7 - wday(config$forecast_date))
  forecast_data <- model_data |>
    group_by(series, location) |>
    tidyr::complete(date = seq(
      from = max(date) + days(1),
      to = next_saturday + # Horizon must be added from next saturday
        days(config$forecast_horizon[index]),
      by = "days"
    )) |>
    ungroup() |>
    mutate(
      year = year(date),
      week = week(date),
      day_of_week = wday(date)
    ) |>
    mutate(
      year = year - min(year) + 1,
      time = as.integer(date - min(date) + 1),
      season = ifelse(week <= 31, year, year + 1)
    ) |>
    filter(date > max(model_data$date))
  ## Model data: weekly data --------------------------------------------------
} else if (config$timestep_data[index] == "week") {
  model_data <- data_formatted |>
    mutate(series = as.factor(location)) |>
    group_by(series, location) |>
    tidyr::complete(date = seq(min(date), max(date), by = "week")) |>
    ungroup() |>
    # Remake the predictors to fill in the missing ones
    mutate(
      year = year(date),
      week = week(date)
    ) |>
    mutate(
      year = year - min(year) + 1,
      time = floor(as.integer(date - min(date) + 1) / 7) + 1,
      season = ifelse(week <= 31, year, year + 1)
    ) |>
    select(time, date, obs_data, series, location, year, season, week)

  # Create forecast data to pass into mvgam
  next_saturday <- ymd(config$forecast_date) + (7 - wday(config$forecast_date))
  last_obs_complete_date <- data_formatted |>
    ungroup() |>
    filter(day_of_week == 7) |>
    summarise(max_date = max(date)) |>
    pull(max_date)

  forecast_data <- model_data |>
    group_by(series, location) |>
    tidyr::complete(date = seq(
      from = last_obs_complete_date + days(7),
      to = next_saturday + # Horizon must be added from next saturday
        weeks(config$forecast_horizon[index]),
      by = "weeks"
    )) |>
    ungroup() |>
    mutate(
      year = year(date),
      week = week(date)
    ) |>
    mutate(
      year = year - min(year) + 1,
      time = floor(as.integer(date - min(date) + 1) / 7) + 1,
      season = ifelse(week <= 31, year, year + 1)
    ) |>
    filter(date > max(model_data$date)) |>
    select(time, date, obs_data, series, location, year, season, week)
}

if (config$pred_type[index] == "pct") {
  model_data <- model_data |>
    # Will need to add 0 and 1 lower and upper bounds
    mutate(obs_data = obs_data / 100)
}

plot_data <-
  ggplot(model_data) +
  geom_line(aes(x = date, y = obs_data, color = as.factor(season)),
    show.legend = FALSE
  ) +
  facet_wrap(~location, scales = "free_y") +
  theme_bw()
ggsave(
  filename = file.path(fp_figs, "raw_data.png"),
  plot = plot_data
)

# Save data -----------------------------------------------------------------
save(model_data,
  file = file.path(
    fp_data,
    glue::glue("{model_data_filename}.rda")
  )
)

save(forecast_data,
  file = file.path(
    fp_data,
    glue::glue("{model_data_filename}_forecast.rda")
  )
)
