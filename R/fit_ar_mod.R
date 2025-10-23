fit_ar_mod <- function(model_data,
                       forecast_data,
                       fp_base,
                       forecast_date) {
  model_run_location <- unique(model_data$model_run_location)
  target <- unique(model_data$target)

  model_data_fit <- model_data |>
    mutate(series = as.factor(location)) |>
    select(time, target_end_date, observation, series, location, year, season, week)

  forecast_data_fit <- forecast_data |>
    mutate(series = as.factor(location)) |>
    select(time, target_end_date, observation, series, location, year, season, week)

  if (str_detect(target, "pct")) {
    model_data_fit <- model_data_fit |>
      mutate(observation = ifelse(observation == 0, 1e-10, observation))
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
  # fp_long <- file.path(fp_figs, model_run_location)
  # dir_create(fp_long)
  #
  # # Save a bunch of figures
  # week_coeffs <- plot_predictions(ar_mod,
  #                                 condition = c("week", "series"),
  #                                 points = 0.5, conf_level = 0.5
  # ) +
  #   labs(y = "Counts", x = "week")
  # ggsave(
  #   plot = week_coeffs,
  #   filename = file.path(fp_long, "week_coeffs.png")
  # )
  #
  # conditional_effects(ar_mod)
  #
  # trace_sigma <- mcmc_plot(ar_mod,
  #                          variable = "sigma",
  #                          regex = TRUE,
  #                          type = "trace"
  # )
  # ggsave(
  #   plot = trace_sigma,
  #   filename = file.path(fp_long, "trace_sigma.png")
  # )
  # trace_ar_coeff <- mcmc_plot(ar_mod,
  #                             variable = "ar1",
  #                             regex = TRUE,
  #                             type = "areas"
  # )
  # ggsave(
  #   plot = trace_ar_coeff,
  #   filename = file.path(fp_long, "trace_ar_coeff.png")
  # )
  #
  # slopes <- plot_slopes(ar_mod,
  #                       variable = "week",
  #                       condition = c("series", "series"),
  #                       type = "link"
  # ) +
  #   theme(legend.position = "none") +
  #   labs(y = "Log(counts)", x = "Location")
  # ggsave(
  #   plot = slopes,
  #   filename = file.path(fp_long, "slopes.png")
  # )
  #
  # # Hierarchical trend effects
  # # trends <- plot(ar_mod, type = "smooths", trend_effects = TRUE)
  # # ggsave(
  # #   plot = trends,
  # #   filename = file.path(fp_figs, "trends.png")
  # # )
  # # Hierarchical intercepts
  # if(length(unique(model_data_fit$series))>1){
  #   intercepts <- plot(ar_mod, type = "re", trend_effects = TRUE)
  #   ggsave(
  #     plot = intercepts,
  #     filename = file.path(fp_long, "intercepts.png")
  #   )
  # }
  #
  example_forecast <- plot(ar_mod, type = "forecast", series = 1)
  ggsave(
    plot = example_forecast,
    filename = file.path(fp_figs, "example_forecast.png")
  )

  return(ar_mod)
}
