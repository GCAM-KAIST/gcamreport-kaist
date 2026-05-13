# Debug actual cf_iea values for wind
library(tidyverse)
library(here)

source(file.path(here(), "kaist/config.R"))

# Load the data files
load(file.path(here(), "data/cf_gcam_v7.0.rda"))
load(file.path(here(), "data/cf_rgn_v7.0.rda"))
load(file.path(here(), "data/iea_capacity_v7.0.rda"))

cat("========== cf_gcam for wind technologies ==========\n")
cf_gcam_v7.0 %>%
  filter(grepl("wind", technology, ignore.case = TRUE)) %>%
  select(technology, `1971`, `2100`) %>%
  print()

cat("\n========== cf_rgn for South Korea wind ==========\n")
cf_rgn_v7.0 %>%
  filter(region == "South Korea", grepl("wind", stub.technology, ignore.case = TRUE)) %>%
  print()

cat("\n========== IEA Capacity for Wind (World/South Korea) ==========\n")
iea_capacity_v7.0 %>%
  filter(grepl("Wind", variable)) %>%
  filter(scenario == "Current Policies Scenario") %>%
  select(variable, region, period, value) %>%
  arrange(variable, region, period) %>%
  print(n = 50)
