fit_model_targets <- list(
  tar_target(
    name = ar_model,
    command = fit_ar_mod(
      model_data = model_data_grouped |>
        filter(model_run_location %in%
          c("Colorado", "CO")),
      forecast_data = forecast_data_grouped |>
        filter(model_run_location %in%
          c("Colorado", "CO")),
      fp_base = "output",
      forecast_date = forecast_date
    ),
    pattern = map(model_data_grouped, forecast_data_grouped),
    format = "rds",
    iteration = "list"
  )
)
