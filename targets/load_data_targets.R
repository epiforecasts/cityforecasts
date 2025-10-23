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
  ),
  tar_target(
    name = all_nyc_data,
    command = read_csv(nyc_data_url) |>
      filter(as_of == max(as_of))
  ),
  tar_target(
    name = all_local_fips_data,
    command = all_nyc_data |>
      filter(tolower(location) %in% c(location_data_local_fips$location))
  ),
  tar_target(
    name = nycwide_data,
    command = all_nyc_data |>
      filter(location == "NYC") |>
      select(target_end_date, location, observation, target)
  ),
  # Combine the state/aggregate level data ---------------------------------
  tar_target(
    name = state_nssp_clean,
    command = all_state_data |>
      rename(
        target_end_date = time_value,
        location = geo_value,
        observation = value
      ) |>
      mutate(
        location = toupper(location),
        target = "Flu ED visits pct"
      ) |>
      select(target_end_date, location, observation, target)
  ),
  tar_target(
    name = agg_level_data,
    command = bind_rows(nycwide_data, state_nssp_clean)
  ),
  tar_target(
    name = state_data_to_model,
    command = if (exclude_covid) {
      agg_level_data |> filter(
        target_end_date <
          ymd(covid_exclusion_period[1]),
        target_end_date >
          ymd(covid_exclusion_period[2])
      )
    } else {
      agg_level_data
    }
  )
  # Combine the local level data ---------------------------------------
)
