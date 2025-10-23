fit_model_targets <- list(
  tar_target(
    name = ar_model,
    command = fit_ar_mod(
      model_data = model_data_grouped,
      forecast_data = forecast_data_grouped,
      fp_base = "output",
      forecast_date = forecast_date
    ),
    pattern = map(model_data_grouped, forecast_data_grouped)
  ),
  tar_target(
    name = plot_forecast_draws,
    command = get_plot_forecasts(
      dfall = ar_model,
      forecast_date = forecast_date,
      fp_figs = file.path("output", "figures")
    ),
    pattern = map(ar_model),
    format = "rds",
    iteration = "list"
  )
)
