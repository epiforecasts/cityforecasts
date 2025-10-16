create_forecast_date_loc_targets <- list( #nolint
  tar_target(
    name = location_data,
    command = read_csv(config$locations_csv_path)
  ),
  tar_target(
    name = state_codes,
    command = tidycensus::fips_codes |>
      select(state, state_code) |>
      distinct()
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
  )
)
