load_data_targets <- list(
  # Get the data for each group of locations
  tar_target(
    name = all_state_data,
    command = pub_covidcast(
      source = "nssp",
      signals = "pct_ed_visits_influenza",
      geo_type = "state",
      geo_values = tolower(location_data_states$state_abb),
      time_type = "week",
      as_of = NULL
    )
  ),
  # Get the local level HSA data from CFA GitHUb (will be out of date right
  # now because of the shut down)
  # eventually replace with another call to `pub_covidcast`
  tar_target(
    name = all_local_hsa_data,
    command = read_csv(nssp_raw_data_url) |>
      filter(
        hsa_nci_id %in% location_data_local_hsa$original_location_code,
        !is.na(percent_visits_influenza),
      ) |>
      select(week_end, geography, hsa, hsa_nci_id, percent_visits_influenza)
  ),
  tar_target(
    name = all_nyc_data,
    command = read_csv(nyc_data_url) |>
      filter(as_of == max(as_of)) |>
      mutate(location = tolower(location)) |>
      mutate(location = ifelse(location == "staten island", "staten-island",
        location
      ))
  ),
  tar_target(
    name = all_local_fips_data,
    command = all_nyc_data |>
      filter(location %in% c(location_data_local_fips$location)) |>
      mutate(model_run_location = "NYC") |>
      select(target_end_date, location, model_run_location, observation, target)
  ),
  tar_target(
    name = nycwide_data,
    command = all_nyc_data |>
      filter(location == "nyc") |>
      mutate(model_run_location = glue::glue("{location}_wide")) |>
      select(target_end_date, location, model_run_location, observation, target)
  ),
  # Combine the state/aggregate level data ---------------------------------
  tar_target(
    name = state_nssp_clean,
    command = all_state_data |>
      rename(
        target_end_date = time_value,
        state_abb = geo_value,
        observation = value
      ) |>
      mutate(
        state_abb = toupper(state_abb),
        target = "Flu ED visits pct"
      ) |>
      left_join(
        location_data |>
          filter(original_location_code == "All") |>
          select(location, state_abb),
        by = "state_abb"
      ) |>
      mutate(model_run_location = glue::glue("{state_abb}_state")) |>
      select(target_end_date, location, model_run_location, observation, target)
  ),
  tar_target(
    name = agg_level_data,
    command = bind_rows(nycwide_data, state_nssp_clean) |>
      filter(target_end_date < forecast_date) |>
      distinct()
  ),
  tar_target(
    name = state_data_to_model,
    command = if (exclude_covid) {
      agg_level_data |> filter(
        !(target_end_date > ymd(covid_exclusion_period[1]) &
          target_end_date <
            ymd(covid_exclusion_period[2]))
      )
    } else {
      agg_level_data
    }
  ),
  # Combine the local level data ---------------------------------------
  tar_target(
    name = hsa_data_clean,
    command = all_local_hsa_data |>
      rename(
        target_end_date = week_end,
        observation = percent_visits_influenza
      ) |>
      mutate(
        target = "Flu ED visits pct"
      ) |> left_join(
        location_data |>
          select(state_abb, location, original_location_code),
        by = c("hsa_nci_id" = "original_location_code")
      ) |>
      mutate(model_run_location = state_abb) |>
      select(target_end_date, location, model_run_location, observation, target)
  ),
  tar_target(
    name = local_data,
    command = bind_rows(hsa_data_clean, all_local_fips_data) |>
      filter(target_end_date < forecast_date) |>
      distinct()
  ),
  tar_target(
    name = local_data_to_model,
    command = if (exclude_covid) {
      local_data |> filter(
        !(target_end_date > ymd(covid_exclusion_period[1]) &
          target_end_date <
            ymd(covid_exclusion_period[2]))
      )
    } else {
      agg_level_data
    }
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
