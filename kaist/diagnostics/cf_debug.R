# CF Debugging Bundle
#
# Combined from earlier one-off debug scripts. Each section can be run on
# its own. Sections progress from simple inspection of cf_gcam / cf_rgn
# values to the cf_iea double-counting bug demonstration.
#
# Sections:
#  1. cf_gcam / cf_rgn value inspection (was: check_cf_all.R, check_cf_gcam.R)
#  2. cf_iea actual data inspection (was: debug_cf_actual.R, debug_cf_flow.R, debug_cf_iea_calculation.R)
#  3. cf_iea bug demonstration with synthetic data (was: debug_cf_calculation.R, debug_cf_final.R)

# ============================================================
# Section 1: cf_gcam / cf_rgn value inspection
# ============================================================
# === from check_cf_all.R ===
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

# === from check_cf_gcam.R ===
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

# ============================================================
# Section 2: cf_iea actual data inspection
# ============================================================
# === from debug_cf_actual.R ===
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

# === from debug_cf_flow.R ===
# Debug the complete CF flow to understand duplicate issue
library(tidyverse)
library(here)

source(file.path(here(), "kaist/config.R"))

# Load data files
load(file.path(here(), "data/cf_gcam_v7.0.rda"))
load(file.path(here(), "data/cf_rgn_v7.0.rda"))

cat("========== Step 1: tmp1 from cf_gcam ==========\n")
# Simulate tmp1 creation (line 4768-4774)
tmp1 <- cf_gcam_v7.0 %>%
  select(technology, cf = `2100`) %>%
  mutate(region = "USA", vintage = 2025) %>%
  tidyr::complete(tidyr::nesting(technology, cf),
                  vintage = seq(2025, 2100, by = 5),
                  region = c("South Korea"))  # Simplified

tmp1 %>%
  filter(grepl("^wind$", technology)) %>%
  select(technology, region, vintage, cf) %>%
  print()

cat("\n========== Step 2: tmp2 from cf_rgn ==========\n")
# Simulate tmp2 creation (line 4776-4777)
tmp2 <- cf_rgn_v7.0 %>%
  filter(region == "South Korea", grepl("^wind$", stub.technology)) %>%
  select(region, technology = stub.technology, vintage = year, cf.rgn = capacity.factor)

print(tmp2)

cat("\n========== Step 3: After left_join and replace ==========\n")
# Simulate the left_join and replace (line 4787-4791)
step3 <- tmp1 %>%
  filter(grepl("^wind$", technology)) %>%
  left_join(tmp2, by = c("technology", "vintage", "region")) %>%
  mutate(cf = replace(cf, !is.na(cf.rgn), cf.rgn[!is.na(cf.rgn)]))

step3 %>% select(technology, region, vintage, cf, cf.rgn) %>% print()

cat("\n========== Step 4: Simulate cf_iea ==========\n")
# cf_iea has historical CF expanded to all vintages (line 4738-4744)
# Let's assume cf_iea for wind is around 0.25 (global average)
cf_iea_simulated <- tibble(
  technology = "wind",
  cf = 0.08,  # Testing with a lower value to see effect
  vintage = c(1990, 1995, 2000, 2005, 2010, 2015, 2020, 2025, 2030, 2035, 2040, 2045, 2050),
  region = "South Korea"
)

cat("Simulated cf_iea (assuming global avg CF = 0.08):\n")
print(cf_iea_simulated)

cat("\n========== Step 5: After bind_rows ==========\n")
# Simulate bind_rows (line 4793)
step5 <- bind_rows(step3, cf_iea_simulated)

step5 %>%
  filter(grepl("^wind$", technology), vintage %in% c(2025, 2030, 2035)) %>%
  select(technology, region, vintage, cf) %>%
  arrange(vintage, cf) %>%
  print()

cat("\nNotice: vintage 2030 appears TWICE with different CF values!\n")

cat("\n========== Step 6: After approx_fun (the bug) ==========\n")
# Define approx_fun
approx_fun <- function(year, value, rule = 1) {
  stats::approx(as.vector(year), value, rule = rule, xout = year)$y
}

# This is what causes the averaging of duplicates
step6 <- step5 %>%
  filter(grepl("^wind$", technology)) %>%
  tidyr::complete(tidyr::nesting(technology, region),
                  vintage = sort(c(1990, 1995, 2000, 2005, 2010, 2015, 2020, 2025, 2030, 2035, 2040, 2045, 2050))) %>%
  group_by(technology, region) %>%
  mutate(cf_final = approx_fun(vintage, cf, rule = 2)) %>%
  ungroup()

cat("After approx_fun - see how CF for 2030 becomes averaged:\n")
step6 %>%
  filter(vintage %in% c(2025, 2030, 2035)) %>%
  select(technology, region, vintage, cf, cf_final) %>%
  distinct(vintage, .keep_all = TRUE) %>%
  print()

cat("\n========== Summary ==========\n")
cat("cf_rgn for wind South Korea: 0.23\n")
cat("cf_iea simulated (global avg): 0.08\n")
cat("After approx_fun averaging: (0.23 + 0.08) / 2 =", (0.23 + 0.08) / 2, "\n")
cat("\nThis explains why Auto CF (~0.15) is lower than configured CF (0.23)!\n")

# === from debug_cf_iea_calculation.R ===
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

# ============================================================
# Section 3: cf_iea bug demonstration with synthetic data
# ============================================================
# === from debug_cf_calculation.R ===
# Debug script to understand CF calculation issue
library(tidyverse)
library(here)

# Test what happens with duplicate vintage entries in approx_fun

# Simulate the scenario:
# After bind_rows, we have duplicate entries for wind, South Korea, 2030
test_data <- tibble(
  technology = "wind",
  region = "South Korea",
  vintage = c(2025, 2030, 2035, 2030),  # 2030 appears twice!
  cf = c(0.23, 0.23, 0.23, 0.15)  # cf_rgn=0.23, cf_iea=0.15 for 2030
)

cat("Test data (simulating bind_rows with duplicates):\n")
print(test_data)

# This is what gcamreport does:
approx_fun <- function(year, value, rule = 1) {
  if (rule == 1 | rule == 2) {
    res <- tryCatch(
      {
        stats::approx(as.vector(year), value, rule = rule, xout = year)$y
      },
      error = function(e) {
        message("An error occured: ", conditionMessage(e))
        return(NA)
      }
    )
  }
  return(res)
}

result <- test_data %>%
  group_by(technology, region) %>%
  mutate(cf_interpolated = approx_fun(vintage, cf, rule = 2)) %>%
  ungroup()

cat("\nAfter approx_fun:\n")
print(result)

cat("\n\nActual stats::approx behavior with duplicates:\n")
x <- c(2025, 2030, 2035, 2030)  # duplicate 2030
y <- c(0.23, 0.23, 0.23, 0.15)  # different values

cat("Input x (vintages):", x, "\n")
cat("Input y (cf values):", y, "\n")

# stats::approx requires sorted, unique x values
# When there are duplicates, it may take the first occurrence or fail
tryCatch({
  result_approx <- stats::approx(x, y, xout = c(2025, 2030, 2035), rule = 2)
  cat("approx output for 2030:", result_approx$y[2], "\n")
}, error = function(e) {
  cat("Error:", conditionMessage(e), "\n")
})

# Test with sorted data
cat("\n\nWith sorted and averaged duplicates:\n")
sorted_data <- tibble(vintage = x, cf = y) %>%
  group_by(vintage) %>%
  summarise(cf = mean(cf)) %>%  # average duplicates
  arrange(vintage)
print(sorted_data)

result_approx2 <- stats::approx(sorted_data$vintage, sorted_data$cf,
                                 xout = c(2025, 2030, 2035), rule = 2)
cat("approx output for 2030 (averaged):", result_approx2$y[2], "\n")

# === from debug_cf_final.R ===
# Final debug to show the averaging bug
library(tidyverse)

# Define approx_fun
approx_fun <- function(year, value, rule = 1) {
  tryCatch({
    stats::approx(as.vector(year), value, rule = rule, xout = year)$y
  }, error = function(e) {
    return(rep(NA, length(year)))
  })
}

cat("========== The Bug: Duplicate vintages get averaged ==========\n\n")

# Create test data simulating bind_rows result
test_data <- tibble(
  technology = "wind",
  region = "South Korea",
  vintage = c(
    # From cf_rgn replacement (step 3)
    2025, 2030, 2035, 2040, 2045, 2050,
    # From cf_iea (step 4) - SAME vintages, different CF!
    2025, 2030, 2035, 2040, 2045, 2050
  ),
  cf = c(
    # cf_rgn values (correct regional CF)
    0.23, 0.23, 0.23, 0.23, 0.23, 0.23,
    # cf_iea values (global average CF - lower)
    0.08, 0.08, 0.08, 0.08, 0.08, 0.08
  )
)

cat("After bind_rows - duplicates exist:\n")
test_data %>%
  arrange(vintage, desc(cf)) %>%
  print()

cat("\n\nAfter approx_fun (stats::approx averages duplicates):\n")
result <- test_data %>%
  group_by(technology, region) %>%
  mutate(cf_result = approx_fun(vintage, cf, rule = 2)) %>%
  ungroup() %>%
  distinct(technology, region, vintage, cf_result)

print(result)

cat("\n========== Summary ==========\n")
cat("Configured regional CF (cf_rgn): 0.23\n")
cat("Global average CF (cf_iea): 0.08\n")
cat("After approx_fun averaging: (0.23 + 0.08) / 2 =", (0.23 + 0.08) / 2, "\n\n")

cat("This is close to the observed Auto CF of ~0.152!\n")
cat("The actual cf_iea value depends on GCAM's secondary energy output,\n")
cat("but the mechanism is confirmed: duplicate vintage entries cause averaging.\n")
