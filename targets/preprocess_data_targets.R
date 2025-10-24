preprocess_data_targets <- list(
  # This should add all the covariates we need such as weekday season etc
  tar_target(
    name = processed_local_data,
    command = preprocess_clean_data(local_data_by_agg),
    pattern = map(local_data_by_agg)
  ),
  tar_target(
    name = processed_local_forecast_data,
    command = get_forecast_data(processed_local_data,
      forecast_date = forecast_date,
      forecast_horizon = max(forecast_horizons)
    ),
    pattern = map(processed_local_data)
  ),
  tar_target(
    name = processed_state_data,
    command = preprocess_clean_data(state_data_by_agg),
    pattern = map(state_data_by_agg)
  ),
  tar_target(
    name = processed_state_forecast_data,
    command = get_forecast_data(processed_state_data,
      forecast_date = forecast_date,
      forecast_horizon = max(forecast_horizons)
    ),
    pattern = map(processed_state_data)
  ),
  tar_target(
    name = model_data,
    command = bind_rows(
      processed_state_data,
      processed_local_data
    )
  ),
  tar_group_by(
    name = model_data_grouped,
    command = model_data ,
    by = model_run_location
  ),
  tar_target(
    name = forecast_data,
    command = bind_rows(
      processed_state_forecast_data,
      processed_local_forecast_data
    )
  ),
  tar_group_by(
    name = forecast_data_grouped,
    command = forecast_data,
    by = model_run_location
  )
)
