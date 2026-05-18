# Detailed debug of capacity calculation
library(tidyverse)
library(here)
library(rgcam)

source(file.path(here(), "kaist/config.R"))

# Load cf data
load(file.path(getwd(), "data/cf_rgn_v7.0.rda"))
load(file.path(getwd(), "data/cf_gcam_v7.0.rda"))

# Load project
prj_files <- list.files(output_dir, pattern = ".*project_.*\\.dat$", full.names = TRUE)
prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
prj <- loadProject(prj_file)

# Get vintage query
elec_gen_vintage <- getQuery(prj, "elec gen by gen tech and cooling tech and vintage")

cat("========== Step 1: Raw wind vintage data (Ref_Con only) ==========\n")
wind_raw <- elec_gen_vintage %>%
  filter(region == "South Korea", year == 2030, scenario == "Ref_Con") %>%
  filter(grepl("wind", technology, ignore.case = TRUE) & !grepl("offshore", technology, ignore.case = TRUE))
print(wind_raw)
cat("\nTotal wind generation (EJ) for Ref_Con:", sum(wind_raw$value), "\n")

cat("\n========== Step 2: Process vintage data (same as step2) ==========\n")
elec_gen_processed <- elec_gen_vintage %>%
  filter(!output %in% c("electricity", "elect_td_bld")) %>%
  tidyr::separate(technology, into = c("tech_full", "vintage_str"), sep = ",", remove = FALSE) %>%
  mutate(
    vintage = as.integer(sub("year=", "", vintage_str)),
    tech_base = gsub("elec_", "", output)
  ) %>%
  bind_rows(
    elec_gen_vintage %>%
      filter(output %in% c("electricity", "elect_td_bld")) %>%
      tidyr::separate(technology, into = c("tech_base", "vintage_str"), sep = ",", remove = FALSE) %>%
      mutate(vintage = as.integer(sub("year=", "", vintage_str)))
  ) %>%
  group_by(scenario, region, tech_base, vintage, year) %>%
  summarise(generation_EJ = sum(value, na.rm = TRUE), .groups = "drop")

wind_processed <- elec_gen_processed %>%
  filter(region == "South Korea", year == 2030, scenario == "Ref_Con", tech_base == "wind")
cat("Processed wind data for Ref_Con:\n")
print(wind_processed)
cat("\nTotal processed wind generation (EJ) for Ref_Con:", sum(wind_processed$generation_EJ), "\n")

# Check wind_storage separately
wind_storage_processed <- elec_gen_processed %>%
  filter(region == "South Korea", year == 2030, scenario == "Ref_Con", tech_base == "wind_storage")
cat("\nProcessed wind_storage data for Ref_Con:\n")
print(wind_storage_processed)

cat("\n========== Step 3: CF lookup ==========\n")
cf_rgn_lookup <- cf_rgn_v7.0 %>%
  select(region, technology = stub.technology, cf_year = year, cf = capacity.factor)

cf_wind <- cf_rgn_lookup %>%
  filter(region == "South Korea", technology == "wind") %>%
  summarise(cf = first(cf)) %>%
  pull(cf)
cat("CF for wind:", cf_wind, "\n")

cf_wind_storage <- cf_rgn_lookup %>%
  filter(region == "South Korea", technology == "wind_storage") %>%
  summarise(cf = first(cf)) %>%
  pull(cf)
cat("CF for wind_storage:", cf_wind_storage, "\n")

cat("\n========== Step 4: Calculate capacity for Ref_Con 2030 ==========\n")
EJ_to_GWh <- 3.6e-6
hr_per_yr <- 8760

# Wind generation
wind_gen <- sum(wind_processed$generation_EJ)
wind_cap <- wind_gen / (cf_wind * hr_per_yr * EJ_to_GWh)
cat("Wind generation (EJ):", wind_gen, "\n")
cat("Wind CF:", cf_wind, "\n")
cat("Wind capacity (GW):", wind_cap, "\n")

# Wind storage generation
if (nrow(wind_storage_processed) > 0) {
  wind_storage_gen <- sum(wind_storage_processed$generation_EJ)
  wind_storage_cap <- wind_storage_gen / (cf_wind_storage * hr_per_yr * EJ_to_GWh)
  cat("\nWind_storage generation (EJ):", wind_storage_gen, "\n")
  cat("Wind_storage CF:", cf_wind_storage, "\n")
  cat("Wind_storage capacity (GW):", wind_storage_cap, "\n")

  cat("\nTotal Wind|Onshore capacity (wind + wind_storage):", wind_cap + wind_storage_cap, "GW\n")
} else {
  cat("\nTotal Wind|Onshore capacity:", wind_cap, "GW\n")
}

cat("\n========== Step 5: Compare with current output ==========\n")
csv_file <- file.path(output_dir, paste0(run_name, ".csv"))
if (file.exists(csv_file)) {
  current_data <- read.csv(csv_file)
  wind_onshore <- current_data %>%
    filter(Region == "South Korea", Variable == "Capacity|Electricity|Wind|Onshore",
           Scenario == "Ref_Con")
  if (nrow(wind_onshore) > 0) {
    cat("Current Wind|Onshore capacity for 2030:", wind_onshore$X2030[1], "GW\n")
    cat("Expected capacity from calculation:", wind_cap + ifelse(exists("wind_storage_cap"), wind_storage_cap, 0), "GW\n")
  }
}

cat("\n========== Step 6: Check tech_to_cap mapping ==========\n")
tech_to_cap <- tribble(
  ~tech_base,       ~cap_var,
  "wind",           "Capacity|Electricity|Wind|Onshore",
  "wind_offshore",  "Capacity|Electricity|Wind|Offshore",
  "wind_storage",   "Capacity|Electricity|Wind|Onshore"  # Check if this should be mapped
)
cat("Current mapping includes wind_storage?\n")
cat("In step2, wind_storage should also map to Wind|Onshore\n")

cat("\n========== Step 7: Check all techs with 'wind' in name ==========\n")
elec_gen_processed %>%
  filter(region == "South Korea", year == 2030, scenario == "Ref_Con",
         grepl("wind", tech_base, ignore.case = TRUE)) %>%
  print()
