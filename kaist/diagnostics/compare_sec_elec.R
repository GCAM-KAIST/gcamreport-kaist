# CF 역산 - Secondary Energy와 Capacity 비교
library(tidyverse)
library(readxl)
library(here)

source(file.path(here(), "kaist/config.R"))

# Load Manual data - Capacity
manual_cap <- read_excel(template_path, sheet = 1) %>%
  rename_with(tolower) %>%
  filter(scenario == "nzM+_Adv") %>%
  filter(grepl("^Capacity\\|Electricity\\|", variable)) %>%
  filter(!grepl("Storage", variable))

# Load Manual data - Secondary Energy
manual_se <- read_excel(template_path, sheet = 1) %>%
  rename_with(tolower) %>%
  filter(scenario == "nzM+_Adv") %>%
  filter(grepl("^Secondary Energy\\|Electricity\\|", variable))

# Load Auto data - Capacity
auto_cap <- read_csv(
  file.path(output_dir, "variables_after_unit_conversion.csv"),
  show_col_types = FALSE
) %>%
  rename_with(tolower) %>%
  filter(scenario == "05_nzM_Adv_plus", region == "South Korea") %>%
  filter(grepl("^Capacity\\|Electricity\\|", variable)) %>%
  filter(!grepl("Storage", variable))

cat("\n========== CF 역산 비교 (2030년) ==========\n")
cat("CF = Secondary Energy (GWh) / (Capacity (GW) × 8760)\n\n")

yr <- "2030"

# Manual
manual_cap_yr <- manual_cap %>%
  select(variable, cap = all_of(yr)) %>%
  mutate(var_base = gsub("Capacity\\|Electricity\\|", "", variable))

manual_se_yr <- manual_se %>%
  select(variable, se = all_of(yr)) %>%
  mutate(var_base = gsub("Secondary Energy\\|Electricity\\|", "", variable))

# Auto
auto_cap_yr <- auto_cap %>%
  select(variable, cap = all_of(yr)) %>%
  mutate(var_base = gsub("Capacity\\|Electricity\\|", "", variable))

# Join and calculate CF
comparison <- manual_cap_yr %>%
  inner_join(manual_se_yr, by = "var_base", suffix = c("_cap", "_se")) %>%
  inner_join(auto_cap_yr %>% select(var_base, cap_auto = cap), by = "var_base") %>%
  mutate(
    cap_manual = as.numeric(cap),
    cap_auto = as.numeric(cap_auto),
    se = as.numeric(se),
    cf_manual = ifelse(cap_manual > 0.001, se / (cap_manual * 8760), NA),
    cf_auto = ifelse(cap_auto > 0.001, se / (cap_auto * 8760), NA),
    cf_ratio = cf_auto / cf_manual
  ) %>%
  select(var_base, cap_manual, cap_auto, se, cf_manual, cf_auto, cf_ratio) %>%
  filter(!is.na(cf_manual) & !is.na(cf_auto)) %>%
  arrange(var_base)

print(comparison, n = 30, width = 200)
