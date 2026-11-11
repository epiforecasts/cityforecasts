load_data_targets_from_hub <- list(
  # Targets to run if using the latest_data directly (the simplest)
  tar_target(
    name = hub_data,
    command = read_csv(latest_data_url),
    # Always re-download so same-day reruns pick up hub data updates;
    # downstream targets only rebuild if the data changed
    cue = tar_cue(mode = "always")
  ),
  # Private California history (not on the hub), read from the local clone.
  # Always reread since the files aren't tracked; downstream targets only
  # rebuild if the data changed
  tar_target(
    name = ca_local_data,
    command = load_ca_data(ca_data_dir, location_data),
    cue = tar_cue(mode = "always")
  ),
  # Hub data plus the local California history for weeks the hub doesn't
  # have (the hub's values are used where both have a week). California is
  # dropped if the local history isn't available, since the hub alone has
  # too few weeks to fit the model.
  # Excludes any locations that have not been updated for the forecast date
  # (latest data is the Saturday before the Wednesday forecast date), except
  # NYC and California, whose data is routinely a week behind, so are allowed
  # one extra week
  tar_target(
    name = all_data,
    command = bind_rows(
      hub_data,
      ca_local_data |>
        anti_join(hub_data, by = c("location", "target", "target_end_date"))
    ) |>
      left_join(location_data, by = "location") |>
      filter(nrow(ca_local_data) > 0 | !state_abb %in% "CA") |>
      group_by(location) |>
      filter(
        max(target_end_date) >= ymd(forecast_date) -
          days(if_else(location == "nyc" | state_abb %in% "CA", 11, 4))
      ) |>
      ungroup()
  ),
  tar_target(
    name = latest_data,
    command = if (exclude_covid) {
      covid_start <- ymd(covid_exclusion_period[1])
      covid_end <- ymd(covid_exclusion_period[2])
      all_data |> filter(
        !(target_end_date > covid_start & target_end_date < covid_end)
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
