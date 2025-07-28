
# Pregistration: Evaluation of real-time performance of local-level flu forecasts in a subset of locations in the United States

## Background

Forecasting Hubs have become a useful tool for coordinating,
communicating, and evaluating short-term forecasts of infectious disease
indicators. The
[`flu-metrocast`](https://github.com/reichlab/flu-metrocast) Hub was
initiated in order to address an interest in both producing and
evaluating the robustness of local-level forecasting in the United
States, with the 2024-2025 season representing a pilot year for the Hub.
Producing robust forecast at the local level can present challenges due
in part to the difficulty of forecasting small population sizes, and
open questions remain regarding the reliability and accuracy of
local-level forecasts, and which methods are most robust for the task.
This project aims to systematically evaluate forecasts generated at the
local level in the United States. The goal of these analyses will be to
address the following questions:

1\. How does local level forecast performance compare to the performance
of aggregated forecasts within and across different models, and how do
characteristics of the locality and the aggregate population impact the
relative value of local forecasting?

2\. Among local forecasts, which models/methods perform best, accounting
for confounding variables that impact a models overall forecast
performance?

This preregistration is intended to ensure that the methods to address
these questions are transparent and clearly stated prior to soliciting
submissions. As much as possible, we aim for compatibility with other US
forecast hubs (e.g. FluSight and US COVID-19 Forecast Hub) targets and
evaluations.

## Forecast targets and submission

### Prediction targets and locations

The Hub will solicit city, county, or metro-area (combination of
counties)-level predictions plus predictions for the corresponding
aggregate location, for the target and horizons relevant to each group
of jurisdictions.

| Target name | Local jurisdictions | Aggregate jurisdiction | Target description | Horizons |
|---------------|---------------|---------------|---------------|---------------|
| ILI ED visits | Bronx, Brooklyn, Queens, Manhattan, and Staten Island | New York City (NYC) | Weekly number of emergency department visits due to influenza-like illness. | 0 to 4 (weeks) |
| Flu ED visits pct | Austin, Houston, Dallas, El Paso, San Antonio | Texas | Weekly percentage of emergency department visits due to influenza. | -1 to 4 (weeks) |
| Flu ED visits pct | *Insert another group of local jurisdictions* | *another state* | Weekly percentage of emergency department visits due to influenza. | -1 to 4 (weeks) |

*Alternative to be considered:* If we foresee issues with soliciting
state-level forecasts due to overlap with FluSight targets, we could
instead remove this piece from the submission solicitation and in the
evaluation analysis, explain that we will plan to use some alternate
aggregate forecast for comparison (e.g. the FluSight ensemble for that
location). This would require that the target be identical to that
solicited for FluSight and the horizons/forecast submission dates and
reference dates be completely aligned.

### Submission format

Predictions will be solicited for weekly values corresponding to the
[CDC definition of
epiweeks](https://wwwn.cdc.gov/nndss/document/MMWR_Week_overview.pdf),
which from Sunday through Saturday. The target end date for a prediction
is the Saturday that ends an epiweek of interest.

For each location and target, teams will be asked to report 9 quantiles
(2.5%, 5%, 10%, 25%, 50%, 75%, 90%, 95%, 97.5%). Teams will submit
prediction for each target end date corresponding to the specified
forecast horizon in weeks.

### Forecast submission dates

The challenge period will begin on October X, 2025 and end on May X,
2026 to align with the FluSight challenge. Participants are asked to
submit forecasts by Monday evenings at 8pm ET. Weekly submissions will
be specified in terms of the reference date, which is the Saturday
following the submissions date. This must be included in the file name
for any model submission.

### Model metadata

All submitted models must contain metadata corresponding to the key
characteristics of the team and the model submission. For this
particular analysis, we will require that teams specify whether or not
the localities within a group were fit jointly or independently within
the methods section of the metadata. This will be used as a variable for
comparing between local models.

## Evaluation

### Forecast metrics

We will score all forecasts for local and aggregate forecasts using the
weighted interval score (WIS) on the log-transformed predictions and
observations, evaluated against the final dataset X days after the final
forecast date. We will decompose WIS into overprediction,
underprediction, and dispersion. To assess calibration, the empirical
coverage of 50% and 90% prediction intervals will be reported.

In both cases, we will use the R package
[`scoringutils`](https://github.com/epiforecasts/scoringutils) to
compute WIS and coverage metrics for individual forecasts and to
summarise scores across different strata.


### Evaluation analysis: local vs aggregate

For this analysis, we will compare the performance of forecasts produced
using each of the local models compared to a per-capita scaled version
of the aggregate level forecast for a particular locality. For example,
if NYC had a forecast of 8,000 hospital admissions on a specific target
date, and one of its boroughs represents 10% of NYC's population, the
aggregate-level forecast for that borough on that date would be 800.
Relative WIS will be computed relative to the corresponding
aggregate-level model. Values of 1 indicate equivalent forecast
performance, values of less than 1 indicate improved performance, and
greater than 1 indicate improved performance compared to the aggregate
level version of the model.

We examine the relative and absolute WIS across multiple
stratifications: overall, by nowcast horizon, and by location.

#### Model-based evaluation of aggregate vs local forecasts

Similar in spirit to Sherratt et al.[1]
we will perform a model-based evaluation to account for confounding
variables impacting the performance of the local model compared to the
aggregate model.

To assess the impact on forecast performance of local forecasting, we
will include the following confounding variables:

-   score of the corresponding aggregate model (as an offset)

-   location

-   forecast date and location together - model

*Observation model* : We'll assume a normally distributed errors on the
WIS scores on the log transformed predictions and observations.

```math
WIS^{local}_{h,d,l,m} \sim Normal(\mu^{local}_{h,d,l,m}, \sigma)
```

*Latent model*: We will model the expected WIS of a particular forecast
horizon $h$ on forecast date $d$ at location $l$ for model $m$ with a
hierarchical GAM.

```math
\mu^{local}_{h,d,l,m} =  \beta + WIS^{aggregate}_{h,d,l,m} + f_{global}(location) + f_{forecast_date}(location) +f(model)
```

 Where $h$ is the forecast horizon (from -1 to 4 weeks), $d$ is the
forecast date, $l$ is the location of the forecast (the borough or metro
area), and $m$ is the model, $f_{global}(location)$, $f_{forecast_date}(location)$ and
$f(model)$ are thin plate splines centered around 0. The forecast-date
location spline $f_{forecast_date}(location)$ is a residual around a
global location spline, $f_{global}(location)$. Here, we want to set up forecast-date
location deviation splines as a residual around a global location
spline, in both case centered around 0. The $WIS^{aggregate}_{h,d,l,m}$
offset should roughly account for the average forecast difficulty of a
particular model at that particular forecast location, forecast date,
and horizon.


We will plot the partial and random effects of each of these components in order to understand the drivers of differences in forecast performance between local and aggregate forecasts.

Additionally, we will investigate various relationships between relative WIS averaged across forecast dates and models compared to characteristics of localities such as population size,
proportion of aggregate population, etc. *Fill in these variables* to generate hypothesis and investigate potential characteristics that may indicate a locality is likely to see
an improvement in forecast performance due to the use of local scale forecasting.

### Evaluation analysis: local model comparison

For this analysis, we will compare the performance of models on the local jurisdictions exclusively, in order to identify models/methods that perform best.
Relative WIS will be computed relative to the baseline model, which projects the last observed week forward for all solicited horizons.

Because not all models were submitted for all forecast dates and locations, it is difficult to assess performance in an unbiased manner.
However, we will compute the geometric average pair relative comparison as this provides a potential work around.

We examine the relative WIS, absolute WIS, and geometric average pair relative comparison across multiple stratifications: overall, by nowcast horizon, and by location.
We will also group models by whether or not they performed joint or independent estimation across the local jurisditions, to assess whether this has an impact on overall forecast performance.

#### Model-based evaluation local model performance
Similar in vein to Sherratt et al[1], we will set up a model-based evaluation to account for confounding variables that impact forecast performance.
These will include:

- location

- forecast date and location

- horizon

- epidemic phase

- model

*Observation model*: Once again we will assume we have normally distributed error around the WIS scores on the log transformed data.
```math
 WIS^{local}_{h,d,l,m} \sim Normal(\mu^{local}_{h,d,l,m}, \sigma)
```

*Latent model*: We will model the expected WIS of a particular forecast horizon $h$ on forecast date $d$ at location $l$ for model $m$ with a hierarchical GAM, this time removing the offset and adding in additional confounding variables likely to impact forecast performance in potentially non-linear ways.

 ```math
 \mu^{local}_{h,d,l,m} =  \beta  + f_{global}(location) + f_{forecast_date}(location) +f(model) + f(horizon) + f(epidemic_phase)
 ```
Where $h$ is the forecast horizon (from -1 to 4 weeks), $d$ is the forecast date, $l$ is the location of the forecast (the borough or metro area), and $m$ is the model.
Where model, horizon, and epidemic phase are all modeled as random effects on the overall scores, and once again the forecast-date location spline $f_{forecast_date}(location)$ is a residual around a global location spline, $f_{global}(location)$.
Again, we want to set up forecast-date location deviation splines as a residual around a global location spline, in both case centered around 0.
The goal of this analysis will be to estimate the effect of the model (via the $s(model, bs = "re")$ term) while taking into account the many additional confounding variables that contribute to forecast performance.
Once again, we will plot the random effect of the model to compare model performance accounting for confounding variables.


## References
[1]: Sherratt K, Fearon E, Muñoz J, et al. The influence of model structure and geographic specificity on predictive accuracy among European COVID-19 forecasts. medRxiv. 2025. doi:10.1101/2025.04.10.25325611
