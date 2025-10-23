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
