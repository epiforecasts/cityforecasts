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
        !is.na(percent_visits_influenza)
      ) |>
      select(week_end, geography, hsa, hsa_nci_id, percent_visits_influenza)
  )
)
