get_plot_data <- function(data,
                          fp_figs,
                          forecast_date,
                          fig_name) {
  agg_location <- ifelse("agg_location" %in% colnames(data),
    unique(data$agg_location),
    unique(data$model_run_location)
  )
  target <- unique(data$target)
  p <- ggplot(data) +
    geom_line(aes(x = target_end_date, y = observation)) +
    facet_wrap(~location) +
    xlab("") +
    ylab(glue::glue("{target}")) +
    geom_vline(aes(xintercept = ymd(forecast_date)),
      linetype = "dashed"
    ) +
    ggtitle(glue::glue("{target} for {agg_location}")) +
    theme_bw()

  dir_create(file.path(fp_figs, agg_location))
  ggsave(
    plot = p,
    filename = file.path(
      fp_figs, agg_location,
      glue::glue("{fig_name}.png")
    )
  )

  return(p)
}

#' Plot forecast draws against the observed data
#'
#' These plots are published in the weekly report, so the observations shown
#' come only from the public hub data (`hub_data`, the hub's latest-data.csv),
#' never from data used to fit the model that isn't on the hub (e.g. the
#' private California history), and no weeks before the hub's first week for
#' a location are shown.
#'
#' @param dfall Draws from `fit_ar_mod()`, with values on the model scale
#'   (proportions for pct targets, counts otherwise).
#' @param hub_data The hub's latest-data.csv, with observations on the hub's
#'   scale (percentages for pct targets, counts otherwise).
get_plot_forecasts <- function(dfall,
                               hub_data,
                               forecast_date,
                               fp_figs,
                               calibration_days_to_show = 90) {
  sampled_draws <- sample(1:max(dfall$draw), 100)
  target <- unique(dfall$target)
  model_run_location <- unique(dfall$model_run_location)
  # The model fits pct targets as proportions, so show them as percentages
  # to match the hub; counts are shown as is
  scale <- if (str_detect(target, "pct")) 100 else 1

  hub_obs <- hub_data |>
    filter(
      .data$target == .env$target,
      location %in% unique(dfall$location)
    ) |>
    select(location, target_end_date, hub_observation = observation)
  hub_start <- hub_obs |>
    summarise(hub_start = min(target_end_date), .by = location)

  df_recent <- dfall |>
    filter(
      target_end_date >= ymd(forecast_date) - days(calibration_days_to_show)
    ) |>
    inner_join(hub_start, by = "location") |>
    filter(target_end_date >= hub_start) |>
    select(-observation) |>
    left_join(hub_obs, by = c("location", "target_end_date"))

  median_df <- df_recent |>
    group_by(target_end_date, location, period) |>
    summarise(median_pred = median(scale * value), .groups = "drop")

  obs_df <- df_recent |>
    distinct(location, target_end_date, hub_observation) |>
    filter(!is.na(hub_observation))

  plot_draws <- ggplot(df_recent |> filter(
    draw %in% c(sampled_draws)
  )) +
    geom_line(
      aes(
        x = target_end_date, y = scale * value,
        group = draw,
        color = period
      ),
      alpha = 0.1,
      show.legend = FALSE
    ) +
    geom_line(data = median_df, aes(
      x = target_end_date,
      y = median_pred,
      color = period
    )) +
    geom_line(data = obs_df, aes(
      x = target_end_date,
      y = hub_observation
    )) +
    geom_point(data = obs_df, aes(
      x = target_end_date,
      y = hub_observation
    ), size = 0.5) +
    facet_wrap(~location, scales = "free_y") +
    theme_bw() +
    xlab("") +
    ylab(target)
  dir_create(file.path(fp_figs, forecast_date, model_run_location))
  ggsave(
    plot = plot_draws,
    filename = file.path(
      fp_figs, forecast_date, model_run_location,
      glue::glue("forecast_draws.png")
    )
  )
  return(plot_draws)
}

get_plot_quantiles <- function(df_quantiled,
                               df_quantiles_wide,
                               reference_date,
                               fp_figs,
                               forecast_date) {
  target <- unique(df_quantiled$target)
  model_run_location <- unique(df_quantiled$model_run_location)
  plot_quantiles <-
    ggplot() +
    geom_line(
      data = df_quantiled |>
        filter(
          target_end_date >= reference_date - weeks(10),
          target_end_date < reference_date
        ),
      aes(x = target_end_date, y = observation),
      linetype = "dashed"
    ) +
    geom_point(
      data = df_quantiled |>
        filter(
          target_end_date >= reference_date - weeks(10),
          target_end_date < reference_date
        ),
      aes(x = target_end_date, y = observation)
    ) +
    facet_wrap(~location, scales = "free_y") +
    geom_line(
      data = df_quantiles_wide,
      aes(x = target_end_date, y = `0.5`)
    ) +
    geom_ribbon(
      data = df_quantiles_wide,
      aes(
        x = target_end_date,
        ymin = `0.25`,
        ymax = `0.75`
      ),
      alpha = 0.2
    ) +
    geom_ribbon(
      data = df_quantiles_wide,
      aes(
        x = target_end_date,
        ymin = `0.025`,
        ymax = `0.975`
      ),
      alpha = 0.2
    ) +
    xlab("") +
    ylab(target) +
    ggtitle("Dynamic GAM forecasts") +
    theme_bw()

  dir_create(file.path(fp_figs, forecast_date, model_run_location))
  ggsave(
    plot = plot_quantiles,
    filename = file.path(
      fp_figs, forecast_date, model_run_location,
      glue::glue("forecast_quantiles.png")
    )
  )

  return(plot_quantiles)
}
