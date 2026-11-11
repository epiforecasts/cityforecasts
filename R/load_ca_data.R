#' Load the private California historical flu hospital admissions data
#'
#' Combines the historical CSV with the latest version of the versioned
#' parquet file, converts it to the hub's latest-data format and adds
#' state-level rows by summing the regions (the hub's California value is the
#' sum of its regions).
#'
#' @param ca_data_dir Path to the local clone of the California data repo.
#' @param location_data The hub's locations table.
#'
#' @returns A tibble with columns target_end_date, location, target and
#'   observation, or zero rows if `ca_data_dir` doesn't exist.
load_ca_data <- function(ca_data_dir, location_data) {
  empty <- tibble(
    target_end_date = as.Date(character()),
    location = character(),
    target = character(),
    observation = numeric()
  )
  if (!dir.exists(ca_data_dir)) {
    warning(
      "California data folder not found at ", ca_data_dir,
      "; skipping California"
    )
    return(empty)
  }

  historical_file <- list.files(
    ca_data_dir, "^historical_flu_data_share_.*\\.csv$",
    full.names = TRUE
  )
  versioned_file <- list.files(
    ca_data_dir, "^versioned_flu_data_share_.*\\.parquet$",
    full.names = TRUE
  )
  if (length(historical_file) != 1 || length(versioned_file) != 1) {
    stop(
      "Expected one historical CSV and one versioned parquet file in ",
      ca_data_dir
    )
  }

  historical <- read_csv(historical_file, show_col_types = FALSE)
  versioned <- arrow::read_parquet(versioned_file) |>
    ungroup() |>
    filter(version_date == max(version_date))

  # Versioned rows first so distinct() keeps its (more recent) value where
  # both files have a week
  regions <- bind_rows(
    versioned |> select(weekending_date, location, location_level, flu_admits),
    historical |> select(weekending_date, location, location_level, flu_admits)
  ) |>
    filter(location_level == "region") |>
    mutate(weekending_date = as.Date(weekending_date)) |>
    distinct(weekending_date, location, .keep_all = TRUE) |>
    transmute(
      target_end_date = as.Date(weekending_date),
      location = str_replace_all(tolower(location), " ", "-"),
      target = "Flu hosp admits",
      observation = flu_admits
    )

  unknown <- setdiff(unique(regions$location), location_data$location)
  if (length(unknown) > 0) {
    stop(
      "California locations not in the hub's locations.csv: ",
      paste(unknown, collapse = ", ")
    )
  }

  # Only sum weeks where every region reported, so a missing region doesn't
  # look like a drop in the state total
  n_regions <- n_distinct(regions$location)
  state <- regions |>
    group_by(target_end_date, target) |>
    filter(n() == n_regions) |>
    summarise(observation = sum(observation), .groups = "drop") |>
    mutate(location = "california")

  bind_rows(regions, state) |>
    arrange(location, target_end_date)
}
