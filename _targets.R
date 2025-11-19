# Targets script for generating weekly forecasts

# The pipeline can be run using `tar_make()`

library(targets)
library(tarchetypes)
library(dplyr)
library(ggplot2)
library(readr)
library(here)
library(purrr)
library(lubridate)
library(tidyr)
library(glue)
library(fs)
library(rlang)
library(epidatr)
library(RcppTOML)
library(cmdstanr)
library(mvgam)
library(stringr)
library(gratia)

# load functions
functions <- list.files(here("R"), full.names = TRUE)
walk(functions, source)
rm("functions")

# load target modules
targets <- list.files(here("targets"), full.names = TRUE)
targets <- grep("*\\.R", targets, value = TRUE)
purrr::walk(targets, source)

tar_option_set(
  packages = c(
    "dplyr",
    "ggplot2",
    "readr",
    "lubridate",
    "tidyr",
    "glue",
    "epidatr",
    "stringr",
    "gratia",
    "mvgam"
  ),
  workspace_on_error = TRUE,
  storage = "worker",
  retrieval = "worker",
  memory = "transient",
  garbage_collection = TRUE,
  format = "parquet", # default storage format
  error = NULL
)


# Get the locations to forecast
set_up <- list(
  create_config_targets
)

# Load in the data for each location
load_data <- list(
  load_data_targets
  # load_data_targets_alt
)

preprocess_data <- list(
  preprocess_data_targets
)

fit_models <- list(
  fit_model_targets
)

post_processing <- list(
  post_processing_targets
)

list(
  set_up,
  load_data,
  preprocess_data,
  fit_models,
  post_processing_targets
)
