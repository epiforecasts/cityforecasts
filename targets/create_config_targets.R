create_config_targets <- list( # nolint
  # Config variables-----------------------------------------------------------
  # Retrospective forecast date from last season
  tar_target(
    name = forecast_date,
    command = "2026-01-21" # Wednesday forecast date
  ),
  tar_target(
    name = reference_date,
    command = ymd(forecast_date) + days(3)
  ),
  tar_target(
    name = real_time,
    command = TRUE
  ),
  tar_target(
    name = filepath_forecasts,
    command = "output/cityforecasts"
  ),
  tar_target(
    name = exclude_covid,
    command = TRUE
  ),
  tar_target(
    name = covid_exclusion_period,
    command = c("2020-02-01", "2022-03-01")
  ),
  tar_target(
    name = forecast_horizons,
    command = 0:3
  ),
  tar_target(
    name = locations_csv_path,
    command = "https://raw.githubusercontent.com/reichlab/flu-metrocast/refs/heads/main/auxiliary-data/locations.csv"
  ),
  # This is the table of all the locations we need to forecast
  tar_target(
    name = location_data,
    command = read_csv(locations_csv_path)
  ),
  tar_target(
    name = state_codes,
    command = tidycensus::fips_codes |>
      select(state, state_code) |>
      distinct()
  ),
  tar_target(
    name = latest_data_url,
    command = "https://raw.githubusercontent.com/reichlab/flu-metrocast/refs/heads/main/target-data/latest-data.csv"
  ),
  tar_target(
    name = nssp_raw_data_url,
    command = "https://raw.githubusercontent.com/CDCgov/covid19-forecast-hub/refs/heads/main/auxiliary-data/nssp-raw-data/latest.csv" # nolint
  ),
  tar_target(
    name = nyc_data_url,
    command = "https://raw.githubusercontent.com/reichlab/flu-metrocast/refs/heads/main/target-data/time-series.csv"
  ),
  tar_target(
    name = loc_data_w_state_code,
    command = location_data |>
      left_join(state_codes, by = c("state_abb" = "state"))
  ),
  # Make into separate targets based on how we will run the model
  # HSAs which will be grouped by state for model fitting-------------------
  tar_target(
    name = location_data_local_hsa,
    command = loc_data_w_state_code |>
      filter(
        location_type == "hsa_nci_id",
        original_location_code != "All"
      ) |>
      mutate(geo_value = paste(state_code, original_location_code, sep = ""))
  ),
  # States which will each be fit independently------------------------------
  tar_target(
    name = location_data_states,
    command = loc_data_w_state_code |>
      filter(original_location_code == "All")
  ),
  # Non-HSAs which will be grouped by state for model fitting--------------
  tar_target(
    name = location_data_local_fips,
    command = loc_data_w_state_code |>
      filter(location_type == "fips")
  ),
  # Aggregate locations that are not states---------------------------------
  tar_target(
    name = location_data_agg,
    command = loc_data_w_state_code |>
      filter(location == "nyc")
  ),
  tar_target(
    name = locations_forecasted,
    command = location_data$location
  ),
  tar_target(
    name = config,
    command = list(
      forecast_date = forecast_date,
      reference_date = reference_date,
      team_name = "epiforecasts",
      model_name = "dyngam",
      exclude_covid = exclude_covid,
      forecast_horizons = forecast_horizons,
      real_time = real_time,
      locations_forecasted = locations_forecasted,
      for_submission = ifelse(real_time, TRUE, FALSE)
    )
  ),
  tar_target(
    name = create_path,
    command = fs::dir_create(file.path(
      filepath_forecasts,
      forecast_date
    ))
  ),
  tar_target(
    name = save_config,
    command = yaml::write_yaml(config,
      file = file.path(
        filepath_forecasts,
        forecast_date,
        "config.yaml"
      )
    )
  )
)
