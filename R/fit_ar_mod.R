fit_ar_mod <- function(model_data,
                       forecast_data,
                       fp_base,
                       forecast_date) {
  model_run_location <- unique(model_data$model_run_location)
  character_id <- unique(model_data$character_id)
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


  # Per-location shift added to the observations before fitting and
  # subtracted from the predictions after (pct targets only)
  shift <- NULL
  if (str_detect(target, "pct")) {
    # Lognormal can't take zeros, so fit it to observation + c, with c a
    # per-location shift (see zero_shift()). The saved model is therefore
    # fit to the shifted data
    shift <- zero_shift(model_data_fit)
    model_data_fit <- model_data_fit |>
      left_join(shift, by = "location") |>
      mutate(observation = observation + shift) |>
      select(-shift)

    # Centre the level prior on the typical log proportion (mean
    # log(observation) across pct locations is ~ -5.5)
    level_prior <- "normal(-5.5, 1)"
    obs_family <- lognormal()
  } else {
    # Target is not a proportion but a count (e.g. hospital admissions) --
    # use a negative binomial observation model, as counts are overdispersed
    # relative to a Poisson

    # Centre the level prior on log(typical count): the log of each location's
    # median count (floored at 1 to avoid log(0)), averaged across locations.
    # SD of 2 on the log scale (~x7 either way) as counts are not stable
    log_typical_count <- model_data_fit |>
      group_by(location) |>
      summarise(log_median = log(max(median(observation, na.rm = TRUE), 1))) |>
      pull(log_median) |>
      mean()
    level_prior <- paste0("normal(", round(log_typical_count, 2), ", 2)")
    obs_family <- nb()
  }

  # The level parameters depend on whether the model is hierarchical
  if (length(unique(model_data_fit$series)) > 1) {
    # Hierarchical random intercepts from s(trend, bs = "re")
    level_priors <- c(
      prior_string(level_prior, class = "mu_raw_trend"),
      prior(exponential(0.33), class = sigma_raw_trend)
    )
  } else {
    # Single location: level is set by the trend intercept
    level_priors <- prior_string(level_prior, class = "Intercept_trend")
  }

  # For pct targets, a lognormal observation model: constant relative noise, so
  # the latent trend can track changes at low proportions (beta treats them as
  # noise)
  ar_mod <- mvgam(
    # Observation formula, empty to only consider the observation process
    formula = observation ~ -1,

    # Process model formula that includes regional intercepts
    trend_formula = trend_formula,
    knots = list(week = c(1, 52)),
    trend_model = "AR1",
    # Adjust the priors
    priors = c(
      level_priors,
      prior(exponential(1), class = sigma),
      prior(normal(0.5, 0.25), class = ar1, lb = 0, ub = 1)
    ),
    data = model_data_fit,
    newdata = forecast_data_fit,
    backend = "cmdstanr",
    family = obs_family
  )

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
      character_id = character_id,
      target = target
    )

  # Undo the shift: y = (y + c) - c, floored at 0 so draws can be exactly 0.
  # `observation` comes from the unshifted model_data, so only `value` changes
  if (!is.null(shift)) {
    dfall <- dfall |>
      left_join(shift, by = "location") |>
      mutate(value = pmax(value - shift, 0)) |>
      select(-shift)
  }


  return(dfall)
}

#' Per-location shift for fitting a lognormal to data with zeros
#'
#' The lognormal can't take zeros, so it is fit to observation + c and c is
#' subtracted from the predictions. In small locations a zero usually means no
#' flu visits among few ED visits, so the smallest non-zero value (one visit)
#' is far above zero. Replacing zeros with a fixed tiny value (previously
#' 0.00005) sits several units below the rest of the data on the log scale,
#' which inflates the observation SD and gives implausibly wide upper tails
#' (#110). c is half the location's smallest non-zero observation, or 0.00005
#' (half the 0.0001 reporting resolution) if it has no non-zero observations.
#'
#' @param data Data frame with `location` and `observation` columns
#' @return Data frame with one row per location and columns `location` and
#'   `shift`
zero_shift <- function(data) {
  data |>
    group_by(location) |>
    summarise(
      shift = if (any(observation > 0, na.rm = TRUE)) {
        min(observation[observation > 0], na.rm = TRUE) / 2
      } else {
        0.00005
      },
      .groups = "drop"
    )
}
