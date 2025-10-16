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
  tar_target(
    name = all_local_hsa_data,
    command = pub_covidcast(
      source = "nssp",
      signals = "pct_ed_visits_influenza",
      geo_type = "hrr", # This should be hsa but I don't see as an input
      geo_values = location_data_local_hsa$original_location_code, # not sure what to use here
      time_type = "week",
      as_of = NULL
    )
  )
)
