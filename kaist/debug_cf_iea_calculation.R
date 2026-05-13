# Debug cf_iea calculation for wind
library(tidyverse)
library(here)

source(file.path(here(), "kaist/config.R"))

# Load the data files
load(file.path(here(), "data/convert_v7.0.rda"))
load(file.path(here(), "data/iea_capacity_v7.0.rda"))
load(file.path(here(), "data/capacity_map_v7.0.rda"))

cat("========== Conversion factors ==========\n")
print(convert_v7.0)

cat("\n========== IEA Capacity for Wind (2020) ==========\n")
iea_wind <- iea_capacity_v7.0 %>%
  filter(grepl("Wind", variable), scenario == "Current Policies Scenario", period == 2020)
print(iea_wind)

cat("\n========== Capacity Map for Wind ==========\n")
capacity_map_v7.0 %>%
  filter(grepl("wind", technology, ignore.case = TRUE)) %>%
  select(technology, var, output) %>%
  distinct() %>%
  print()

# Simulate cf_iea calculation
# This is what get_cf_iea_tmp does:
# cf = EJ / (value * hr_per_yr * EJ_to_GWh)

hr_per_yr <- convert_v7.0[['hr_per_yr']]
EJ_to_GWh <- convert_v7.0[['EJ_to_GWh']]

cat("\n\n========== Simulating cf_iea calculation ==========\n")
cat("hr_per_yr:", hr_per_yr, "\n")
cat("EJ_to_GWh:", EJ_to_GWh, "\n")

# Assume global wind secondary energy in 2020 was about 1.6 EJ
# (World wind generation ~1600 TWh = 0.00576 EJ)
# Actually, let me check: 1 TWh = 3.6e-3 EJ, so 1600 TWh = 5.76 EJ? That can't be right...
# 1 TWh = 0.0036 EJ, so 1600 TWh = 5.76 EJ. Hmm.

# Let me calculate backwards:
# If CF = 0.30 (reasonable global wind CF)
# Capacity = 684 GW
# Energy = 684 * 0.30 * 8760 = 1,797,552 GWh = 1.798 PWh = 1.798e6 GWh
# In EJ: 1.798e6 GWh / 277780 GWh/EJ = 6.47 EJ

global_wind_cap_GW <- 684
assumed_cf <- 0.30
energy_GWh <- global_wind_cap_GW * assumed_cf * hr_per_yr
energy_EJ <- energy_GWh / (1e6 / 3.6)  # 1 EJ = 277,778 GWh

cat("\nAssumed global wind CF:", assumed_cf, "\n")
cat("IEA Wind Capacity (2020):", global_wind_cap_GW, "GW\n")
cat("Expected Energy:", energy_GWh, "GWh =", energy_EJ, "EJ\n")

# Now calculate CF using the gcamreport formula
# cf = EJ / (value * hr_per_yr * EJ_to_GWh)
cf_calculated <- energy_EJ / (global_wind_cap_GW * hr_per_yr * EJ_to_GWh)
cat("\nCF calculated using gcamreport formula:\n")
cat("cf = EJ / (GW * hr_per_yr * EJ_to_GWh)\n")
cat("cf =", energy_EJ, "/", "(", global_wind_cap_GW, "*", hr_per_yr, "*", EJ_to_GWh, ")\n")
cat("cf =", cf_calculated, "\n")

# The correct formula should give CF back:
# Energy (EJ) = Capacity (GW) * CF * hours * (1/EJ_per_GWh)
# So: CF = Energy (EJ) / (Capacity (GW) * hours / EJ_per_GWh)
#        = Energy (EJ) * EJ_per_GWh / (Capacity (GW) * hours)
cat("\nExpected result should be approximately:", assumed_cf, "\n")
cat("If the calculated CF is very different, there's a conversion error\n")
