# check_cf_reverse.R
# Reverse-calculate CF (Capacity Factor) from Generation / Capacity
# CF = Generation (EJ) / (Capacity (GW) × 8760 × 3.6e-6)

library(dplyr)
library(tidyr)
library(readr)

# Load data
data <- read_csv("c:/GCAM/gcamreport/kmip/DB25_output/kaist_report_korea.csv", show_col_types = FALSE)

# Constants
hr_per_yr <- 8760
EJ_to_GWh <- 3.6e-6  # 1 GWh = 3.6e-6 EJ

# Technology mapping: Generation variable -> Capacity variable
tech_mapping <- tribble(
  ~gen_var, ~cap_var, ~tech_name,
  "Secondary Energy|Electricity|Biomass", "Capacity|Electricity|Biomass", "Biomass",
  "Secondary Energy|Electricity|Biomass|w/ CCS", "Capacity|Electricity|Biomass|w/ CCS", "Biomass w/ CCS",
  "Secondary Energy|Electricity|Biomass|w/o CCS", "Capacity|Electricity|Biomass|w/o CCS", "Biomass w/o CCS",
  "Secondary Energy|Electricity|Coal", "Capacity|Electricity|Coal", "Coal",
  "Secondary Energy|Electricity|Coal|w/ CCS", "Capacity|Electricity|Coal|w/ CCS", "Coal w/ CCS",
  "Secondary Energy|Electricity|Coal|w/o CCS", "Capacity|Electricity|Coal|w/o CCS", "Coal w/o CCS",
  "Secondary Energy|Electricity|Gas", "Capacity|Electricity|Gas", "Gas",
  "Secondary Energy|Electricity|Gas|w/ CCS", "Capacity|Electricity|Gas|w/ CCS", "Gas w/ CCS",
  "Secondary Energy|Electricity|Gas|w/o CCS", "Capacity|Electricity|Gas|w/o CCS", "Gas w/o CCS",
  "Secondary Energy|Electricity|Oil", "Capacity|Electricity|Oil", "Oil",
  "Secondary Energy|Electricity|Oil|w/ CCS", "Capacity|Electricity|Oil|w/ CCS", "Oil w/ CCS",
  "Secondary Energy|Electricity|Oil|w/o CCS", "Capacity|Electricity|Oil|w/o CCS", "Oil w/o CCS",
  "Secondary Energy|Electricity|Nuclear", "Capacity|Electricity|Nuclear", "Nuclear",
  "Secondary Energy|Electricity|Hydro", "Capacity|Electricity|Hydro", "Hydro",
  "Secondary Energy|Electricity|Geothermal", "Capacity|Electricity|Geothermal", "Geothermal",
  "Secondary Energy|Electricity|Solar", "Capacity|Electricity|Solar", "Solar",
  "Secondary Energy|Electricity|Solar|PV", "Capacity|Electricity|Solar|PV", "Solar PV",
  "Secondary Energy|Electricity|Solar|CSP", "Capacity|Electricity|Solar|CSP", "Solar CSP",
  "Secondary Energy|Electricity|Wind", "Capacity|Electricity|Wind", "Wind",
  "Secondary Energy|Electricity|Wind|Onshore", "Capacity|Electricity|Wind|Onshore", "Wind Onshore",
  "Secondary Energy|Electricity|Wind|Offshore", "Capacity|Electricity|Wind|Offshore", "Wind Offshore"
)

# Year columns
year_cols <- c("2020", "2025", "2030", "2035", "2040", "2045", "2050")

# Extract generation data (EJ/yr)
gen_data <- data %>%
  filter(Variable %in% tech_mapping$gen_var) %>%
  select(Scenario, Variable, all_of(year_cols)) %>%
  pivot_longer(cols = all_of(year_cols), names_to = "year", values_to = "generation_ej")

# Extract capacity data (GW)
cap_data <- data %>%
  filter(Variable %in% tech_mapping$cap_var) %>%
  select(Scenario, Variable, all_of(year_cols)) %>%
  pivot_longer(cols = all_of(year_cols), names_to = "year", values_to = "capacity_gw")

# Join and calculate CF
cf_result <- gen_data %>%
  left_join(tech_mapping, by = c("Variable" = "gen_var")) %>%
  left_join(
    cap_data %>% rename(cap_var_actual = Variable),
    by = c("Scenario", "year", "cap_var" = "cap_var_actual")
  ) %>%
  mutate(
    # CF = Generation (EJ) / (Capacity (GW) × 8760 × 3.6e-6)
    cf = ifelse(
      capacity_gw > 0,
      generation_ej / (capacity_gw * hr_per_yr * EJ_to_GWh),
      NA_real_
    ),
    cf_pct = round(cf * 100, 1)
  ) %>%
  select(scenario = Scenario, tech_name, year, generation_ej, capacity_gw, cf, cf_pct) %>%
  arrange(scenario, tech_name, year)

# Print results for 2030
cat("\n========== CF Reverse Calculation Results (2030) ==========\n\n")

cf_2030 <- cf_result %>%
  filter(year == "2030") %>%
  select(scenario, tech_name, generation_ej, capacity_gw, cf_pct) %>%
  arrange(scenario, desc(cf_pct))

for (scen in unique(cf_2030$scenario)) {
  cat(sprintf("\n--- %s ---\n", scen))
  cf_2030 %>%
    filter(scenario == scen, !is.na(cf_pct), capacity_gw > 0.01) %>%
    mutate(
      generation_ej = round(generation_ej, 4),
      capacity_gw = round(capacity_gw, 2)
    ) %>%
    select(-scenario) %>%
    print(n = 30)
}

# Print all years for key technologies
cat("\n\n========== CF by Year (Key Technologies) ==========\n")

key_techs <- c("Nuclear", "Coal", "Gas", "Solar PV", "Wind Onshore", "Wind Offshore", "Hydro")

cf_yearly <- cf_result %>%
  filter(tech_name %in% key_techs, capacity_gw > 0.01) %>%
  select(scenario, tech_name, year, cf_pct) %>%
  pivot_wider(names_from = year, values_from = cf_pct)

for (scen in unique(cf_yearly$scenario)) {
  cat(sprintf("\n--- %s ---\n", scen))
  cf_yearly %>%
    filter(scenario == scen) %>%
    select(-scenario) %>%
    print(n = 20)
}

# Save full results to CSV
output_file <- "c:/GCAM/gcamreport/kmip/DB25_output/cf_reverse_calculated.csv"
write_csv(cf_result, output_file)
cat(sprintf("\n\nFull results saved to: %s\n", output_file))
