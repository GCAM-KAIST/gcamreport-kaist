# Check all cf_gcam values
library(tidyverse)
library(here)

load(file.path(here(), "data/cf_gcam_v7.0.rda"))
load(file.path(here(), "data/cf_rgn_v7.0.rda"))

cat("========== ALL cf_gcam_v7.0 technologies ==========\n")
cf_gcam_v7.0 %>%
  select(technology, cf = `2100`) %>%
  arrange(technology) %>%
  print(n = 100)

cat("\n========== cf_rgn for South Korea (unique technologies) ==========\n")
cf_rgn_v7.0 %>%
  filter(region == "South Korea") %>%
  select(technology = stub.technology, cf = capacity.factor) %>%
  distinct() %>%
  arrange(technology) %>%
  print(n = 50)
