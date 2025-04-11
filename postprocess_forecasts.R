##### Rscript that will generate hub formatted forecasts ####
library(argparser, quietly = TRUE)
library(RcppTOML)
library(dplyr)
library(mvgam)
library(cmdstanr)
library(lubridate)
library(purrr)
library(tidyr)
library(blogdown)
library(ggplot2)

list.files(file.path("R"), full.names = TRUE) |>
  walk(source)

# Command Line Version --------------------------------------------------------
parsed_args <- arg_parser("Preprocess the data for a config") |>
  add_argument("config", help = "Path to TOML config file") |>
  parse_args()

if (!is.na(parsed_args$config)) {
  # config <- parseTOML("input/example_config_weekly.toml") #nolint
  config <- parseTOML(parsed_args$config)
} else {
  message("File specified in config filepath does not exist")
}

# Large loop running around all the indices to get the files needed for
# all model fits
