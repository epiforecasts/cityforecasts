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
    "epidatr"
  ),
  workspace_on_error = TRUE,
  storage = "worker",
  retrieval = "worker",
  memory = "transient",
  garbage_collection = TRUE,
  format = "parquet", # default storage format
  error = "null"
)

# Load in the config file
config <- parseTOML(file.path("input", "config.toml"))

# Get the locations to forecast
set_up <- list(
  create_forecast_date_loc_targets
)

# Load in the data for each location
load_data <- list(
  load_data_targets
)

list(
  set_up,
  load_data
)
