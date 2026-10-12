format_forecasts <- function(df_weekly,
                             reference_date,
                             n_draws_to_submit = 100) {
  target <- unique(df_weekly$target)[!is.na(unique(df_weekly$target))]
  model_run_location <- unique(df_weekly$model_run_location)

  max_data_date <- df_weekly |>
    filter(!is.na(observation)) |>
    summarise(max_data_date = max(target_end_date)) |>
    distinct() |>
    pull(max_data_date)

  index_num <- 1:n_draws_to_submit
  character_id <- unique(df_weekly$character_id)

  draws_df <- data.frame(
    draws = sample(1:max(df_weekly$draw), n_draws_to_submit,
      replace = FALSE
    ),
    output_type_id = glue::glue("{character_id}{index_num}")
  )

  df_weekly_posteriors <- df_weekly |>
    filter(
      target_end_date >= ymd(reference_date) - days(90),
      draw %in% draws_df$draws
    ) |>
    left_join(draws_df, by = c("draw" = "draws")) |>
    select(-draw) |>
    arrange(
      location, reference_date,
      as.numeric(stringr::str_extract(output_type_id, "[0-9.]+"))
    ) |>
    mutate(
      output_type = "sample",
      target = {{ target }},
      reference_date = reference_date,
      max_data_date = max_data_date,
      model_run_location = model_run_location
    ) |>
    select(
      reference_date, location, observation,
      target, target_end_date,
      output_type, output_type_id, value,
      max_data_date,
      model_run_location
    )

  if (str_detect(target, "pct")) {
    df_weekly_posteriors <- df_weekly_posteriors |>
      mutate(
        value = 100 * value,
        observation = 100 * observation
      )
  }

  return(df_weekly_posteriors)
}

save_draws <- function(df_for_submission,
                       forecast_date,
                       reference_date,
                       filepath_forecasts) {
  dir_create(file.path(filepath_forecasts, forecast_date))
  fp <- file.path(
    filepath_forecasts,
    forecast_date,
    glue::glue("{reference_date}-epiforecasts-dyngam.parquet")
  )
  arrow::write_parquet(df_for_submission, fp)
  as.character(fp)
}
