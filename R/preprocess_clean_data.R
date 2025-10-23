preprocess_clean_data <- function(data) {
  agg_location <- ifelse("agg_location" %in% colnames(data),
    unique(data$agg_location),
    unique(data$location)
  )

  model_data <- data |>
    mutate(series = as.factor(location)) |>
    group_by(series, location) |>
    tidyr::complete(target_end_date = seq(min(target_end_date),
      max(target_end_date),
      by = "week"
    )) |>
    ungroup() |>
    mutate(
      year = year(target_end_date),
      week = week(target_end_date),
    ) |>
    mutate(
      year = year - min(year) + 1,
      time = floor(as.integer(target_end_date - min(target_end_date) + 1) / 7) + 1,
      season = ifelse(week <= 31, year, year + 1)
    ) |>
    select(
      time, target_end_date,
      observation, series, location, year, season, week, target
    ) |>
    mutate(model_run_location = agg_location)

  if ("pct" %in% unique(data$target)) {
    model_data <- model_data |>
      mutate(observation = observation / 100)
  }
  return(model_data)
}

get_forecast_data <- function(model_data,
                              forecast_date,
                              forecast_horizon) {
  next_saturday <- ymd(forecast_date) + (7 - wday(forecast_date))

  model_run_location <- unique(model_data$model_run_location)
  target <- unique(model_data$target)[1]

  forecast_data <- model_data |>
    group_by(series, location) |>
    tidyr::complete(
      target_end_date = seq(
        from = next_saturday,
        to = next_saturday + days(7 * forecast_horizon),
        by = "weeks"
      )
    ) |>
    ungroup() |>
    mutate(
      year = year(target_end_date),
      week = week(target_end_date)
    ) |>
    mutate(
      year = year - min(year) + 1,
      time = floor(as.integer(target_end_date - min(target_end_date) + 1) / 7) + 1,
      season = ifelse(week <= 31, year, year + 1)
    ) |>
    filter(target_end_date > max(model_data$target_end_date)) |>
    select(
      time, target_end_date,
      observation, series, location, year, season, week
    ) |>
    mutate(
      target = target,
      model_run_location = model_run_location
    )


  return(forecast_data)
}
