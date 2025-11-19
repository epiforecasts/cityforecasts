format_forecasts <- function(df_weekly,
                             reference_date,
                             quantiles_to_submit = c(0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975)) {
  target <- unique(df_weekly$target)[!is.na(unique(df_weekly$target))]
  model_run_location <- unique(df_weekly$model_run_location)

  max_data_date <- df_weekly |>
    filter(!is.na(observation)) |>
    summarise(max_data_date = max(target_end_date)) |>
    distinct() |>
    pull(max_data_date)

  df_weekly_quantiled <- df_weekly |>
    filter(target_end_date >= ymd(reference_date) - days(90)) |>
    mutate(horizon = floor(as.integer(ymd(target_end_date) - reference_date)) / 7) |>
    forecasttools::trajectories_to_quantiles(
      quantiles = quantiles_to_submit,
      timepoint_cols = c("target_end_date"),
      value_col = "value",
      id_cols = c(
        "location",
        "horizon", "observation"
      )
    ) |>
    mutate(
      output_type = "quantile",
      target = {{ target }},
      reference_date = reference_date,
      max_data_date = max_data_date,
      model_run_location = model_run_location
    ) |>
    rename(
      output_type_id = quantile_level,
      value = quantile_value
    ) |>
    select(
      reference_date, location, horizon, observation,
      target, target_end_date,
      output_type, output_type_id, value,
      max_data_date,
      model_run_location
    )

  if (str_detect(target, "pct")) {
    df_weekly_quantiled <- df_weekly_quantiled |>
      mutate(
        value = 100 * value,
        observation = 100 * observation
      )
  }

  return(df_weekly_quantiled)
}

save_quantiles <- function(df_for_submission,
                           forecast_date,
                           reference_date,
                           filepath_forecasts) {
  df_for_submission <- df_for_submission |>
    filter(horizon >= 0)
  dir_create(
    filepath_forecasts,
    forecast_date
  )
  write.csv(
    df_for_submission,
    file.path(
      filepath_forecasts,
      forecast_date,
      glue::glue("{reference_date}-epiforecasts-dyngam.csv")
    ),
    row.names = FALSE
  )
  return(NULL)
}
