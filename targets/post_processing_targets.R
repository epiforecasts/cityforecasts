post_processing_targets <- list(
  tar_target(
    name = df_draws,
    command = format_forecasts(
      model_draws,
      reference_date
    ),
    pattern = map(model_draws)
  ),
  tar_target(
    name = df_for_submission,
    # Only submit the hub's forecast horizons (relative to the reference
    # date): from min_horizon_by_target for each target (e.g. 0 for ED visits
    # pct, -1 for CA hospital admissions) to max(forecast_horizons).
    # Computed outside filter() since df_draws also has a reference_date
    # column.
    command = {
      ref_date <- ymd(reference_date)
      min_horizon <- function(target) {
        coalesce(unname(min_horizon_by_target[target]), min(forecast_horizons))
      }
      submission_dates <- function(target) {
        ref_date + weeks(seq(min_horizon(target), max(forecast_horizons)))
      }
      df_draws |>
        filter(
          target_end_date %in% submission_dates(target[1]),
          .by = target
        ) |>
        # Draws are shared across locations fit jointly, but the hub requires
        # each sample ID to belong to a single location (compound_taskid_set
        # is reference_date, target, location), so append a location index.
        mutate(output_type_id = paste0(
          output_type_id, "_", as.integer(factor(location))
        )) |>
        select(
          reference_date, location, target, target_end_date,
          output_type, output_type_id, value
        )
    }
  ),
  tar_target(
    name = save_submission,
    command = save_draws(
      df_for_submission,
      forecast_date,
      reference_date,
      filepath_forecasts
    ),
    format = "file"
  )
)
