# Proposal: `flu-metrocast` retrospective and real-time evaluation to understand the relative value of local forecasting and assess performance of local forecasting models


This document describes the analysis plan to perform both a real-time and retrospective evaluation of the models submitted to the [`flu-metrocast Hub`](https://github.com/reichlab/flu-metrocast) for the 2024-2025 respiratory virus season.
The `flu-metrocast` Hub was developed in order to address a request for more local-level forecasting efforts in the United States.
It serves as a platform for assessing the robustness and accuracy of local-level forecasts, which can in return facilitate improved methods to address the nuances and complexities that arise when working with local level data at small population sizes.
To assess the forecast performance of the localized forecasts in the Hub, we will use both the forecasts in the GitHub repository representing the real-time submissions as well as retrospectively produced forecasts from each of the 4 submitting teams for true and approximated historical snapshots of the data available as of each forecast date for the boroughs of New York City and a selected subset of HSA regions in Texas. Additionally, teams will retrospectively generate aggregate-level forecasts using their model fit only to the aggregate data (either all of New York City combined or all of Texas).
The population-scaled aggregate-level forecasts will be used to represent the "status quo" in absence of local level forecasting, with the implicit assumption being that in absence of local forecasting in presence of a more aggregate forecast, the aggregate-level forecasts dynamics would likely be imposed upon the locality of interest.

## Aims
The goal of these analyses will be to assess:
1. How do local level forecasts compare to aggregate level forecasts in terms of forecast performance across different models?
2. Which models performed best in the local setting in real-time and retrospectively accounting for confounding variables in epidemic phase and data availability?

## Data

This analysis will use publicly available data from the `flu-metrocast` Hub.
The hub contains historical snapshots of the data available as of forecast dates starting in January of 2025 for New York City and February of 2025 for Texas.
To ensure that we are capturing forecast performance across a range of epidemic phases, we reconstruct quasi-snapshots of the data available as of forecast dates starting in October 2025.
These quasi-snapshots will contain the same reporting lag as the real-time snapshots, but will simply consist of truncating the full time-series of data.
Teams will produce forecasts from October 2024 to May 2025.

### Target data
The data for Texas and New York City consists of the following forecast targets:
| Target name | Jurisdictions |  Target description |
|------------------------|------------------------|------------------------|
| ILI ED visits | New York City (NYC), Bronx, Brooklyn, Queens, Manhattan, and Staten Island | Weekly number of emergency department visits due to influenza-like illness. |
| Flu ED visits pct | Austin, Houston, Dallas, El Paso, San Antonio | Weekly percentage of emergency department visits due to influenza. |

For New York City, models predict new ED visits due to ILI for the epidemiological week (EW) ending on the reference date (horizon = 0) as well as for horizons 1 through 4.
For Texas cities, models predict the percentage of new ED visits due to influenza for horizons -1 to 4.

## Models
We will solicit retrospective forecasts from all teams that submitted models to the Hub in real-time. These include:

- Copycat
- GBQR
- INFLAenza
- lop_norm
- dyngam
- baseline

For each model in the local jurisdictions, we will ask that teams additionally produce a forecast for the aggregate data (so all of New York City or all of Texas, both of which data will be provided for), using only the data at the aggregate level.

## Evaluation
The evaluation will broadly be broken up into two dimensions:
- aggregate vs local model comparison and within-local model comparison
- real-time and retrospective

### Retrospective analysis: aggregate vs local model comparison
For this analysis, we will compare the performance of forecasts produced using each of the local models compared to a per-capita scaled version of the aggregate level forecast super-imposed on the locality.
For example, if NYC had a forecast of 8,000 hospital admissions on a specific target date, and one of its boroughs represents 10% of NYC's population, the aggregate-level forecast for that borough on that date would be 800.

We will score forecasts using the weighted interval score (WIS) on the log-transformed predictions and observations, evaluated against the final dataset X days after the final forecast date using the quantiles solicited in the `flu-metrocast` Hub (0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975).
We will decompose WIS into dispersion, overprediction, and underprdiction as well as compute coverage metrics for all models, local and aggregate.
Relative WIS will be computed relative to the corresponding aggregate-level model.
Values of 1 indicate equivalent forecast performance, values of less than 1 indicate improved performance, and greater than 1 indicate improved performance compared to the aggregate level version of the model.

We examine the relative and absolute WIS across multiple stratifications: overall, by nowcast horizon, and by location.

#### Model-based evaluation of aggregate vs local forecasts

Similar in spirit to Sherratt et al, we will perform a model-based evaluation to account for confounding variables impacting the performance of the local model compared to the aggregate model.

To assess the impact on forecast performance of local forecasting, we will include the following confounding variables:
- score of the corresponding aggregate model (as an offset)
- forecast date and location together
- location
- model

Resulting in the following model formulation:
$$
WIS^{local}_{h,d,l,m} \sim \beta + WIS^{aggregate}_{h,d,l,m} + s(location, bs = "re") + s(forecastdate, by = "location") + s(model, bs = "re")
$$
Where $h$ is the forecast horizon (from -1 to 4 weeks), $d$ is the forecast date, $l$ is the location of the forecast (the borough or metro area), and $m$ is the model.
The $WIS^{aggregate}_{h,d,l,m}$ term should roughly account for the average forecast difficulty of a particular model at that particular forecast location, forecast date, and horizon.

We can roughly interpret $\beta$ as the average effect of local forecasting on forecast performance compared to the aggregate forecast, and the $s(model, bs = "re")$ term as the average additional effect across all locations, forecast dates, and horizons from a particular model.

The $s(location, bs = "re")$ term tells us about the additional effect of location on the relative value of local forecasting, whereas the $s(forecastdate, by = location)$ term tells us about the effect of the forecast date and location combinations on forecast performance.

We will plot the partial effects of each of these components in order to understand the drivers of differences in forecast performance between local and aggregate forecasts.

### Retrospective analysis: local model comparison
Because all models will produce forecasts retrospectively for all locations and forecast dates, for this component we can focus on aggregate and stratified scores by location and forecast date.

### Real-time analysis: local model comparison
Using the quantiles already submitted to the Hub from the models in real-time we will score forecasts using the WIS.
Relative WIS will be computed relative to the baseline model.

Because not all models were submitted for all forecast dates and locations, with only a handful of models submitted for the complete set of forecast dates, it is difficult to assess performance in an unbiased manner.

#### Model-based evaluation of real-time local model performance
Similar in vein to Sherratt et al, we will set up a model-based evaluation to account for confounding variables that impact forecast performance.
These will include:
- location
- forecast date and location
- horizon
- epidemic phase
- model


$$
WIS^{local}_{h,d,l,m} \sim \beta + s(location, bc = "re") + s(forecast_date, by = "location") + s(horizon, k) + s(epidemic_phase, bs = "re") + s(model, bs = "re")
$$
Where $h$ is the forecast horizon (from -1 to 4 weeks), $d$ is the forecast date, $l$ is the location of the forecast (the borough or metro area), and $m$ is the model.
The goal of this analysis will be to estimate the effect of the model (via the $s(model, bs = "re")$ term) while taking into account the many additional confounding variables that contribute to forecast performance.
Once again, we will plot the partial effect of the model to compare model performance accounting for confounding variables.
