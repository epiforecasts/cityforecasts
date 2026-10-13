# Backtest the original model (beta, AR1 ~ N(0.5, 0.25)) against the updated
# model (lognormal, AR1 ~ N(0.9, 0.1), level priors) on pct data from last
# season. For each location group and forecast date, the data are truncated at
# the forecast date, both models are fit, and the 4-week-ahead forecast draws
# are compared with what was later observed.
#
# Caveat: truncation uses the current (final) data, so this ignores any
# reporting revisions/backfill that would have been present in real time.

library(targets)
library(tidyverse)
library(mvgam)
library(scoringutils)

tar_load(model_data_grouped)

# ---- Settings ----------------------------------------------------------------

# Location groups (model_run_location) to backtest: one single-location model
# and several multi-location hierarchical models
groups <- c("NY", "MA", "TX", "CO")

# Date of the last observation used to fit each backtest, spanning last
# season's onset, growth, peak, decline and spring wave
forecast_dates <- ymd(c(
  "2025-11-01", "2025-11-22", "2025-12-20", "2026-01-17", "2026-03-07"
))
n_weeks_ahead <- 4

# Range of observed data to show in the plots
plot_from <- ymd("2025-09-01")
plot_to <- ymd("2026-05-01")
n_draws_plot <- 100

out_dir <- "scratch/backtest_output"
dir_create <- function(x) dir.create(x, showWarnings = FALSE, recursive = TRUE)
dir_create(out_dir)

# ---- Model definitions ---------------------------------------------------------

get_trend_formula <- function(n_series) {
  if (n_series > 1) {
    ~ s(trend, bs = "re") +
      s(week, k = 12, bs = "cc") +
      s(week, k = 12, bs = "cc", by = trend) - 1
  } else {
    ~ s(week, k = 12, bs = "cc")
  }
}

# Original model, as in R/fit_ar_mod.R
fit_original <- function(data, newdata) {
  data <- data |>
    mutate(observation = ifelse(observation == 0, 1e-10, observation))
  mvgam(
    formula = observation ~ -1,
    trend_formula = get_trend_formula(nlevels(data$series)),
    knots = list(week = c(1, 52)),
    trend_model = "AR1",
    priors = c(
      prior(normal(-4.5, 1), class = mu_raw_trend),
      prior(exponential(0.33), class = sigma_raw_trend),
      prior(exponential(1), class = sigma),
      prior(normal(0.5, 0.25), class = ar1, lb = 0, ub = 1)
    ),
    data = data,
    newdata = newdata,
    backend = "cmdstanr",
    family = betar(),
    silent = 2
  )
}

# Lognormal model, as in scratch/adjust_model.R, with the AR order and AR
# priors as arguments
fit_lognormal <- function(data, newdata, p, ar_priors, ...) {
  # Data are rounded to 0.0001, so a zero means < 0.00005
  data <- data |>
    mutate(observation = ifelse(observation == 0, 0.00005, observation))
  if (nlevels(data$series) > 1) {
    level_priors <- c(
      prior(normal(-5.5, 1), class = mu_raw_trend),
      prior(exponential(0.33), class = sigma_raw_trend)
    )
  } else {
    level_priors <- prior(normal(-5.5, 1), class = Intercept_trend)
  }
  mvgam(
    formula = observation ~ -1,
    trend_formula = get_trend_formula(nlevels(data$series)),
    knots = list(week = c(1, 52)),
    trend_model = AR(p = p),
    priors = c(
      level_priors,
      prior(exponential(1), class = sigma),
      ar_priors
    ),
    data = data,
    newdata = newdata,
    backend = "cmdstanr",
    family = lognormal(),
    silent = 2,
    ...
  )
}

models <- list(
  original = fit_original,
  # Lognormal, AR1 with persistence prior (current scratch/adjust_model.R)
  updated = \(data, newdata) fit_lognormal(data, newdata, p = 1, c(
    prior(normal(0.9, 0.1), class = ar1, lb = 0, ub = 1)
  )),
  # Lognormal, AR1 with the original AR prior: separates likelihood vs prior
  ln_ar1_05 = \(data, newdata) fit_lognormal(data, newdata, p = 1, c(
    prior(normal(0.5, 0.25), class = ar1, lb = 0, ub = 1)
  )),
  # Lognormal, AR2 with the original prior on ar1. With ar1 <= 1 the process
  # can't extrapolate a trend (momentum needs ar1 ~ 2, ar2 ~ -1)
  ln_ar2_05 = \(data, newdata) fit_lognormal(data, newdata, p = 2, c(
    prior(normal(0.5, 0.25), class = ar1, lb = 0, ub = 1),
    prior(normal(0, 0.5), class = ar2, lb = -1, ub = 1)
  )),
  # Lognormal, AR2 with ar1 allowed above 1 so the recent direction of
  # change can be carried forward (not constrained to be stationary).
  # Higher adapt_delta as the default gave divergences for NYC
  ln_ar2_mom = \(data, newdata) fit_lognormal(data, newdata, p = 2, c(
    prior(normal(1, 0.5), class = ar1, lb = -1, ub = 2),
    prior(normal(0, 0.5), class = ar2, lb = -1, ub = 1)
  ), control = list(adapt_delta = 0.99))
)

# ---- Run backtests -------------------------------------------------------------

run_backtest <- function(group, forecast_date, model_name) {
  message("Fitting ", model_name, " for ", group, " at ", forecast_date)
  group_data <- model_data_grouped |>
    filter(model_run_location == group) |>
    mutate(series = as.factor(location)) |>
    select(time, target_end_date, observation, series, location, year, season, week) |>
    group_by(target_end_date, location) |>
    mutate(observation = mean(observation)) |>
    ungroup() |>
    distinct()

  train <- group_data |> filter(target_end_date <= forecast_date)
  test <- group_data |>
    filter(
      target_end_date > forecast_date,
      target_end_date <= forecast_date + weeks(n_weeks_ahead)
    )

  fit <- models[[model_name]](train, mutate(test, observation = NA))
  fc <- forecast(fit, newdata = mutate(test, observation = NA), type = "response")

  # Forecasts are listed in the order of the series factor levels
  test_dates <- sort(unique(test$target_end_date))
  draws <- map2(fc$forecasts, levels(train$series), \(mat, loc) {
    as_tibble(mat, .name_repair = ~ as.character(test_dates)) |>
      mutate(draw = row_number()) |>
      pivot_longer(-draw, names_to = "target_end_date", values_to = "predicted") |>
      mutate(target_end_date = ymd(target_end_date), location = loc)
  }) |>
    list_rbind() |>
    left_join(
      test |> select(location, target_end_date, observed = observation),
      by = c("location", "target_end_date")
    ) |>
    mutate(
      group = group,
      forecast_date = forecast_date,
      model = model_name,
      horizon = as.integer(target_end_date - forecast_date) / 7
    )

  # Posterior medians of the AR coefficients
  ar_vars <- intersect(c("ar1[1]", "ar2[1]"), variables(fit)$trend_pars$orig_name)
  ar_post <- as.data.frame(fit, variable = ar_vars) |>
    summarise(across(everything(), median))

  n_div <- sum(rstan::get_divergent_iterations(fit$model_output))
  list(draws = draws, diagnostics = tibble(
    group = group, forecast_date = forecast_date, model = model_name,
    divergences = n_div,
    ar1 = ar_post[["ar1[1]"]],
    ar2 = if ("ar2[1]" %in% names(ar_post)) ar_post[["ar2[1]"]] else NA_real_
  ))
}

# Each fit is cached separately, so only new group/date/model combinations
# are fit. Delete scratch/backtest_output/fits/ to refit everything.
fits_dir <- file.path(out_dir, "fits")
dir_create(fits_dir)

runs <- expand_grid(
  group = groups,
  forecast_date = forecast_dates,
  model_name = names(models)
)
results <- pmap(runs, \(group, forecast_date, model_name) {
  f <- file.path(fits_dir, paste0(group, "_", forecast_date, "_", model_name, ".rds"))
  if (!file.exists(f)) saveRDS(run_backtest(group, forecast_date, model_name), f)
  readRDS(f)
})
draws <- map(results, "draws") |>
  list_rbind() |>
  mutate(model = factor(model, levels = names(models)))
diagnostics <- map(results, "diagnostics") |> list_rbind()

# ---- Score ---------------------------------------------------------------------

# CRPS on the natural scale and on the log scale (relative errors, so low
# and high periods count more equally)
scores <- draws |>
  mutate(forecast_date = as.character(forecast_date), model = as.character(model)) |>
  as_forecast_sample(
    forecast_unit = c(
      "group", "location", "forecast_date", "model",
      "target_end_date", "horizon"
    ),
    sample_id = "draw"
  ) |>
  transform_forecasts(fun = log_shift, offset = 0.0001) |>
  score(metrics = list(crps = crps_sample)) |>
  as_tibble()

# Empirical coverage of the central 50% and 90% intervals of the draws
coverage <- draws |>
  group_by(group, location, forecast_date, model, target_end_date) |>
  summarise(
    cov_50 = between(
      first(observed), quantile(predicted, 0.25),
      quantile(predicted, 0.75)
    ),
    cov_90 = between(
      first(observed), quantile(predicted, 0.05),
      quantile(predicted, 0.95)
    ),
    .groups = "drop"
  ) |>
  mutate(forecast_date = as.character(forecast_date), model = as.character(model))

# Mean CRPS (and its ratio to the original model) and interval coverage for
# each model, summarised over the `by` columns
score_summary <- function(by) {
  crps <- scores |>
    group_by(across(all_of(c("model", "scale", by)))) |>
    summarise(crps = mean(crps), .groups = "drop") |>
    group_by(across(all_of(c("scale", by)))) |>
    mutate(crps_ratio_vs_original = crps / crps[model == "original"]) |>
    ungroup() |>
    pivot_wider(names_from = scale, values_from = c(crps, crps_ratio_vs_original))
  cov <- coverage |>
    group_by(across(all_of(c("model", by)))) |>
    summarise(across(c(cov_50, cov_90), mean), .groups = "drop")
  left_join(crps, cov, by = c("model", by)) |>
    mutate(model = factor(model, levels = names(models))) |>
    arrange(across(all_of(c(by, "model"))))
}

overall <- score_summary(character())
by_group <- score_summary("group")
by_group_date <- score_summary(c("group", "forecast_date"))
write_csv(overall, file.path(out_dir, "scores_overall.csv"))
write_csv(by_group, file.path(out_dir, "scores_by_group.csv"))
write_csv(by_group_date, file.path(out_dir, "scores_by_group_date.csv"))
write_csv(diagnostics, file.path(out_dir, "diagnostics.csv"))

print(diagnostics, n = Inf)
print(overall, width = Inf)
print(by_group, width = Inf)
# Log-scale CRPS ratio vs original for each group and forecast date
print(
  by_group_date |>
    select(group, forecast_date, model, crps_ratio_vs_original_log) |>
    pivot_wider(names_from = model, values_from = crps_ratio_vs_original_log),
  n = Inf, width = Inf
)

# ---- Plot ----------------------------------------------------------------------

model_colours <- c(
  original = "#2a78d6", updated = "#eb6834", ln_ar1_05 = "#1baf7a",
  ln_ar2_05 = "#eda100", ln_ar2_mom = "#e87ba4"
)

plot_backtest <- function(grp, log_y = FALSE) {
  d <- draws |> filter(group == grp)
  sampled <- sample(unique(d$draw), min(n_draws_plot, n_distinct(d$draw)))
  observed <- model_data_grouped |>
    filter(
      model_run_location == grp,
      between(target_end_date, plot_from, plot_to)
    ) |>
    distinct(location, target_end_date, observation)
  medians <- d |>
    group_by(location, model, forecast_date, target_end_date) |>
    summarise(median = median(predicted), .groups = "drop")

  p <- ggplot() +
    geom_vline(
      data = tibble(forecast_date = forecast_dates),
      aes(xintercept = forecast_date),
      linetype = "dashed", colour = "grey70", linewidth = 0.3
    ) +
    geom_line(
      data = d |> filter(draw %in% sampled),
      aes(
        x = target_end_date, y = 100 * predicted,
        group = interaction(draw, forecast_date), colour = model
      ),
      alpha = 0.08, linewidth = 0.3
    ) +
    geom_line(
      data = medians,
      aes(
        x = target_end_date, y = 100 * median,
        group = forecast_date, colour = model
      ),
      linewidth = 0.8
    ) +
    geom_line(
      data = observed,
      aes(x = target_end_date, y = 100 * observation),
      colour = "grey20", linewidth = 0.4
    ) +
    geom_point(
      data = observed,
      aes(x = target_end_date, y = 100 * observation),
      colour = "grey20", size = 0.6
    ) +
    scale_colour_manual(values = model_colours, guide = "none") +
    facet_grid(location ~ model, scales = "free_y") +
    theme_bw() +
    theme(panel.grid.minor = element_blank()) +
    labs(
      x = NULL,
      y = "Flu ED visits (%)",
      title = paste0(grp, ": backtest forecasts vs later observed data"),
      subtitle = "Dashed lines: forecast dates. Thin lines: forecast draws; thick: median; black: observed"
    )
  # Floor the log axis at 0.01% so zeros (and near-zero draws) don't squash
  # the panels
  if (log_y) p <- p + scale_y_log10() + coord_cartesian(ylim = c(0.01, NA))
  p
}

for (grp in groups) {
  n_loc <- n_distinct(draws$location[draws$group == grp])
  ggsave(file.path(out_dir, paste0("backtest_", grp, ".png")),
    plot_backtest(grp),
    width = 3 * length(models) + 1, height = 1.8 * n_loc + 1.5
  )
  ggsave(file.path(out_dir, paste0("backtest_", grp, "_log.png")),
    plot_backtest(grp, log_y = TRUE),
    width = 3 * length(models) + 1, height = 1.8 * n_loc + 1.5
  )
}
