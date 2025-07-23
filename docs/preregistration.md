# Pregistration: Evaluation of real-time performance of local-level flu forecasts in a subset of locations in the United States

## Background

Forecasting Hubs have become a useful tool for coordinating, communicating, and evaluating short-term forecasts of infectious disease indicators.
The [`flu-metrocast`](https://github.com/reichlab/flu-metrocast) Hub was initiated in order to address an interest in both producing and evaluating the robustness of local-level forecasting in the United States, with the 2024-2025 season representing a pilot year for the Hub.
Producing robust forecast at the local level can present challenges due in part to the difficulty of forecasting small population sizes, and there still remain open questions regarding the reliability and accuracy of local-level forecasts compared to aggregate forecasts, and which methods are most robust for the task.
This project aims to systematically compare forecasts generated at the local level in the United States. The goal of these analyses will be to address the following questions:
1. How does local level forecast performance compare to the performance of aggregated forecasts within and across different models, and how do demographics of the local setting impact the relative value of local forecasting?
2. Among local forecasts, which models/methods perform best, accounting for confounding variables that impact a models overall forecast performance?

This preregistration is intended to ensure that the methods to address these questions are transparent and clearly stated prior to soliciting submissions. 
As much as possible, we aim for compatibility with other US forecast hubs (e.g. FluSight and US COVID-19 Forecast Hub) targets and evaluations. 

## Forecast targets and submission

### Prediction targets and locations
** Insert table and language from flu metrocast Hub** indicating weekly percent/numbers, target name, and jurisdictions and expected horizons (-1 to 4). 

Explain that for each local level forecast, we will either solicit an aggregate forecast (e.g. either state or city if forecasts are sub-city level) from teams or we will use the ensemble forecast from the state level from flusight as a comparison. 

### Submission format
** Insert language on target data **
reference date = saturday at end of epiweek 
target end date = reference date + horizon

- quantiles solicited

### Forecast submission dates
challenge period aligned with Flusight: October X, 2025- May X, 2026. Timelines will align with FluSight to facilitate direct comparison if required. 


## Evaluation

### Forecast metrics
- WIS
- coverage

### Inclusion criteria
Teams can submit for any number of locations and forecast dates and they will be included in the model-based evaluation. 
However, when averaging across different strata we will only include models that submitted forecasts for:
- 90% of locations
- 90% of forecast dates 
- all horizons
This is to prevent a biased comparison if for example a team only submits for relatively easy forecasting dates or locations. 
The model-based analysis is intended to directly address these potential confounders of forecast performance, thus, we will include all submissions in these analyses. 

### Evaluation analysis: local vs aggregate

### Evaluation analysis: local model comparison
