post_processing_targets <- list(
  tar_target(
    name = df_draws,
    command = format_forecasts(
      model_draws,
      reference_date
    ),
    pattern = map(model_draws)
  ),
  tar_target(
    name = df_for_submission,
    command = df_draws |>
      filter(target_end_date >= max_data_date) |>
      select(
        reference_date, location, target, target_end_date,
        output_type, output_type_id, value
      )
  ),
  tar_target(
    name = save_submission,
    command = save_draws(
      df_for_submission,
      forecast_date,
      reference_date,
      filepath_forecasts
    ),
    format = "file"
  )
)
