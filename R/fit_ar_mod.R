fit_ar_mod <- function(model_data,
                       forecast_data,
                       fp_base,
                       forecast_date) {
  model_run_location <- unique(model_data$model_run_location)
  target <- unique(model_data$target)[!is.na(unique(model_data$target))]

  model_data_fit <- model_data |>
    mutate(series = as.factor(location)) |>
    select(time, target_end_date, observation, series, location, year, season, week) |>
    group_by(target_end_date, location) |>
    mutate(observation = mean(observation)) |>
    ungroup() |>
    distinct()

  forecast_data_fit <- forecast_data |>
    mutate(series = as.factor(location)) |>
    select(time, target_end_date, observation, series, location, year, season, week)

  if (length(unique(model_data_fit$series)) > 1) {
    trend_formula <-
      # Hierarchical intercepts capture variation in average count
      ~ s(trend, bs = "re") +
        # Hierarchical effects of year(shared smooth)
        # s(year, k = 3) +
        # # Borough level deviations
        # s(year, trend, bs = "sz", k = 3) -1 +

        # Hierarchical effects of seasonality (not time varying for now)
        s(week, k = 12, bs = "cc") +
        # Location level deviations
        s(week, k = 12, bs = "cc", by = trend) - 1
  } else {
    # Single location: no hierarchical structure needed
    trend_formula <- ~ s(week, k = 12, bs = "cc")
  }


  if (str_detect(target, "pct")) {
    model_data_fit <- model_data_fit |>
      mutate(observation = ifelse(observation == 0, 1e-10, observation))

    # Multiple locations
    ar_mod <- mvgam(
      # Observation formula, empty to only consider the Gamma observation process
      formula = observation ~ -1,

      # Process model formula that includes regional intercepts
      trend_formula = trend_formula,
      knots = list(week = c(1, 52)),
      trend_model = "AR1",
      # Adjust the priors
      priors = c(
        prior(normal(-4.5, 1),
          class = mu_raw_trend
        ),
        prior(exponential(0.33), class = sigma_raw_trend),
        prior(exponential(1), class = sigma),
        prior(normal(0.5, 0.25), class = ar1, lb = 0, ub = 1)
      ),
      data = model_data_fit,
      newdata = forecast_data_fit,
      backend = "cmdstanr",
      family = betar()
    )
  } else {
    # Target is not a proportion but a count -- need a Poisson observation model
    ar_mod <- mvgam(
      # Observation formula, empty to only consider the Gamma observation process
      formula = observation ~ -1,

      # Process model formula that includes regional intercepts
      trend_formula = trend_formula,
      knots = list(week = c(1, 52)),
      trend_model = "AR1",
      # Adjust the priors
      priors = c(
        prior(normal(-4.5, 1),
          class = mu_raw_trend
        ),
        prior(exponential(0.33), class = sigma_raw_trend),
        prior(exponential(1), class = sigma),
        prior(normal(0.5, 0.25), class = ar1, lb = 0, ub = 1)
      ),
      data = model_data_fit,
      newdata = forecast_data_fit,
      backend = "cmdstanr",
      family = poisson()
    )
  }

  summary <- summary(ar_mod)
  fp_figs <- file.path(fp_base, "figures", forecast_date, model_run_location)
  fp_mod <- file.path(fp_base, "model", forecast_date, model_run_location)
  dir_create(fp_figs)
  dir_create(fp_mod)
  save(ar_mod, file = file.path(
    fp_mod,
    "ar_mod.rda"
  ))
  forecast_obj <- forecast(ar_mod,
    newdata = forecast_data_fit,
    type = "response"
  )
  dfall <- make_long_pred_df(
    forecast_obj = forecast_obj,
    model_data = model_data,
    pred_type = "value",
    timestep = "week"
  ) |>
    mutate(
      model_run_location = model_run_location,
      target = target
    )


  return(dfall)
}
