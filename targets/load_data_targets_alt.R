load_data_targets_alt <- list(
  # Targets to run if using the latest_data directly (the simplest)
  tar_target(
    name = all_data,
    command = read_csv(latest_data_url) |>
      left_join(location_data, by = "location") |>
      rename(observation = oracle_value)
  ),
  tar_target(
    name = latest_data,
    command = if (exclude_covid) {
      all_level_data |> filter(
        !(target_end_date > ymd(covid_exclusion_period[1]) &
          target_end_date <
            ymd(covid_exclusion_period[2]))
      )
    } else {
      all_data
    }
  ),
  tar_target(
    name = state_data_to_model,
    command = latest_data |>
      filter(original_location_code == "All") |>
      mutate(model_run_location = glue::glue("{state_abb}_state")) |>
      select(target_end_date, location, model_run_location, observation, target)
  ),
  tar_target(
    name = local_data_to_model,
    command = latest_data |>
      filter(original_location_code != "All") |>
      mutate(model_run_location = state_abb) |>
      select(target_end_date, location, model_run_location, observation, target)
  ),
  tar_group_by(
    name = local_data_by_agg,
    command = local_data_to_model,
    by = model_run_location
  ),
  tar_group_by(
    name = state_data_by_agg,
    command = state_data_to_model,
    by = model_run_location
  ),
  tar_target(
    name = fp_figs,
    command = file.path(
      "output",
      "figures",
      forecast_date
    )
  ),
  tar_target(
    name = plot_local_data,
    command = get_plot_data(local_data_by_agg,
      fp_figs = fp_figs,
      forecast_date = forecast_date,
      fig_name = "raw_data_local"
    ),
    pattern = map(local_data_by_agg),
    format = "rds",
    iteration = "list"
  ),
  tar_target(
    name = plot_state_data,
    command = get_plot_data(state_data_by_agg,
      fp_figs = fp_figs,
      forecast_date = forecast_date,
      fig_name = "raw_data_agg"
    ),
    pattern = map(state_data_by_agg),
    format = "rds",
    iteration = "list"
  )
)
