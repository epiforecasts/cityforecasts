# cityforecasts
R scripts to generate city-level forecasts 

## Summary 
This repository contains R code to generate city-level forecasts for submission to the [flu-metrocast hub](https://github.com/reichlab/flu-metrocast). 
All models are exploratory/preliminary, though we will regularly update this document to describe the latest mathematical model used in the submission. 

All outputs submitted to the Hub will be archived in this repository, along with additional model metadata (such as the model definition associated with a submission and details on any additional data sources used or decisions made in the submission process). 
If significant changes to the model are made during submission, we will rename the model in the submission file. 

Initially, we plan to fit the data from each state independently, using hierarchical partial pooling to jointly fit the cities within a state. 
This initially includes producing forecast of:
|Forecast target| Location | 
|-----------|-----------|
| ED visits due to ILI | New York City (5 boroughs, unknown, citywide) |
| Percent of ED visits due to flu | Texas (5 metro areas) |

We plan to use the same latent model structure for both forecast targets, modifying the observation model for count data (NYC) vs proportion data (Texas). 

## Workflow
Because all data is available publicly, the forecasts generated should be completely reproducible from the specified configuration file. 
We start by using the [`mvgam`](https://github.com/nicholasjclark/mvgam) package, which is a an R package that leverages both [`mgcv`](https://cran.r-project.org/web/packages/mgcv/index.html) and [`brms`](https://paulbuerkner.com/brms/) formula interface to fit Bayesian Dynamic Generalized Additive Models (GAMs). 
These packages use metaprogramming to produce Stan files, and we also include the Stan code generated by the package. 

To produce forecasts each week we follow the following workflow:

1. Modify the configuration file in `input/{forecast_date}/config.toml`
2. In the command line, run ` Rscript preprocess_data.R `input/{forecast_date}/config.toml`
3. Next run ` Rscript models.R`
4. Lastly run `Rscript postprocess_forecasts.R `input/{forecast_date}/config.toml`
5. This will populate the `output/cityforecasts/{forecast_date}` folder with a csv file formatted following the Hub submission guidelines.

Eventually, steps 2-4 will be automated with the Github Action `.git/workflows/generate_forecasts` and set on a schedule to run after 12 pm CST, corresponding to the time that the `target_data` is updated on the Hub. 

## Model definition 

The below describes the preliminary model used:
### Observation model 
For the forecasts of counts due to ED visits, we assume a Poisson observation process 
```math
y_{l,t} \sim Poisson(exp(x_{l,t})) \\
```
For the forecasts of the percent of ED visits due to flu, we assume a Beta observation process on the proportion of ED visits due to flu:
```math
p_{l,t} = y_{l,t} \times 100
y_{l,t} \sim Beta (z_{l,t}, \phi)
logit(z_{l,t}) = x_{l,t}
```

### Latent state-space model: Dynamic hierachical GAM
We model latent admissions due either to ILI or flu with a hierarchical GAM component to capture shared seasonality and weekday effects and a univariate autoregressive component to capture the trend within each location. 
```math
x_{l,t} \sim Normal(\mu_{l,t} + \delta_{l} x_{l,t-1},  \sigma_l)\\
\mu_{l,t} = \beta_l + f_{global,t}(week) + f_{l,t}(week) + f_{global,t}(wday) \\
\beta_l \sim Normal(\beta_{global}, \sigma_{count}) \\
\beta_{global} \sim Normal(log(avgcount), 1) \\
\sigma_{count} \sim exp(0.33) \\
\delta_l \sim Normal(0.5, 0.25) \\
\sigma \sim exp(1) \\
```

For the NYC data, we have daily data so $t$ is measured in days. 
For the Texas data, the percent of ED visits due to flu is reported weekly, so we exclude the $f_{global,t}(weekday)$ term and $t$ is measured in weeks. 
