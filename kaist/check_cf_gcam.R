# Check cf_gcam values for technologies
library(tidyverse)
library(here)

load(file.path(here(), "data/cf_gcam_v7.0.rda"))

cat("========== cf_gcam_v7.0 values ==========\n")
cf_gcam_v7.0 %>%
  select(technology, `2100`) %>%
  filter(grepl("hydro|coal|gas|biomass|oil|refin", technology, ignore.case = TRUE) |
         grepl("Gen_", technology)) %>%
  arrange(technology) %>%
  print(n = 50)
