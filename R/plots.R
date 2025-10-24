get_plot_data <- function(data,
                          fp_figs,
                          forecast_date,
                          fig_name) {
  agg_location <- ifelse("agg_location" %in% colnames(data),
    unique(data$agg_location),
    unique(data$location)
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

get_plot_forecasts <- function(dfall,
                               forecast_date,
                               fp_figs,
                               calibration_days_to_show = 90) {
  sampled_draws <- sample(1:max(dfall$draw), 100)
  target <- unique(dfall$target)
  model_run_location <- unique(dfall$model_run_location)

  df_recent <- dfall |> filter(
    target_end_date >= ymd(forecast_date) - days(calibration_days_to_show)
  )

  plot_draws <- ggplot(df_recent |> filter(
    draw %in% c(sampled_draws)
  )) +
    geom_line(
      aes(
        x = target_end_date, y = 100 * value,
        group = draw,
        color = period
      ),
      alpha = 0.2,
      show.legend = FALSE
    ) +
    geom_line(aes(
      x = target_end_date,
      y = 100 * observation
    )) +
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
      data = df_weekly_quantiled |>
        filter(
          target_end_date >= reference_date - weeks(10),
          target_end_date < reference_date
        ),
      aes(x = target_end_date, y = obs_data),
      linetype = "dashed"
    ) +
    geom_point(
      data = df_weekly_quantiled |>
        filter(
          target_end_date >= reference_date - weeks(10),
          target_end_date < reference_date
        ),
      aes(x = target_end_date, y = obs_data)
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
