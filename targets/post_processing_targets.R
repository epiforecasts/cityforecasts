post_processing_targets <- list(
  tar_target(
    name = df_quantiled,
    command = format_forecasts(df_recent, reference_date),
    pattern = map(model_draws)
  ),
  tar_target(
    name = df_quantiles_wide,
    command = df_quantiled |>
      filter(
        target_end_date >= forecast_date,
        output_type_id %in% c(0.5, 0.025, 0.975, 0.25, 0.75)
      ) |>
      tidyr::pivot_wider(
        id_cols = c("location", "target_end_date"),
        names_from = "output_type_id"
      ),
    pattern = map(df_quantiled)
  ),
  tar_target(
    name = plot_quantiles,
    command = get_plot_quantiles(
      df_quantiled,
      df_quantiles_wide,
      reference_date = reference_date,
      fp_figs = file.path("output", "figures"),
      forecast_date = forecast_date
    ),
    pattern = map(df_quantiled, df_quantiles_wide)
  ),
  tar_target(
    name = df_for_submission,
    command = df_quantiled |>
      filter(target_end_date >= max_data_date) |>
      select(
        reference_date, location, horizon, target, target_end_date,
        output_type, output_type_id, value
      )
  ),
  tar_target(
    name = save_submission,
    command = write.csv(
      df_for_submission,
      file.path(
        filepath_forecasts,
        forecast_date,
        glue::glue("{reference_date}-epiforecasts-dyngam.csv")
      )
    )
  )
)
