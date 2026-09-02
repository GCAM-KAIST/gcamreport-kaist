################################################################################
# Step 2: Process GCAM Data
#
# PURPOSE:
#   Post-process GCAM report data with additional queries and calculations.
#   - Part A: All Regions (CO2 prices, battery storage, Gen_III_Korea fix)
#   - Part B: Korea Only (emissions reallocation, primary energy calculations)
#
# PREREQUISITES:
#   1. Run kaist/step1_generate_report.R successfully
#   2. Coefficient files in kaist/data/
#
# OUTPUT:
#   - {run_name}.csv: Updated data for all regions
#   - {run_name}_korea.csv: Korea data with additional calculations
#
# NEXT STEP:
#   - kaist/step3_create_mapping.R
#
################################################################################

########## Load Configuration ##########
source(file.path(getwd(), "kaist/config.R"))
########################################

########## Project File (.prj) ##########
# Auto-find latest project file from step1
prj_files <- list.files(output_dir, pattern = paste0("^", run_name, "_project_.*\\.dat$"), full.names = TRUE)
if (length(prj_files) > 0) {
  prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
  cat("Using project file:", basename(prj_file), "\n")
} else {
  stop("No project file found. Run step1_generate_report.R first.")
}
#########################################

########## Apply KAIST data overrides ##########
# Re-apply KAIST customizations to data/*.rda so the upstream
# inst/extdata/saveDataFiles_GCAM*.R can stay 100% unmodified.
# See kaist/functions.R::patch_gcam_data. Must run before load_all.
patch_gcam_data(paste0("v", version_number))
################################################

########## Libraries ##########
devtools::load_all(".", reset = TRUE)
library(dplyr)
library(tidyr)
library(readxl)
library(rgcam)
################################

########## Load KAIST step2 modules ##########
# One file per adjustment (a* = Part A all regions, b* = Part B Korea only).
# Module files only define functions; sourcing them executes nothing.
for (f in list.files(file.path(getwd(), "kaist/modules"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
##############################################

########## Load Data ##########
excel_file <- file.path(output_dir, paste0(run_name, ".xlsx"))
data <- read_excel(excel_file)

prj <- loadProject(prj_file)

gcam_vars <- available_variables_with_units(print = FALSE, GCAM_version = paste0("v", version_number))
write.csv(gcam_vars, file.path(output_dir, "gcam_available_variables.csv"), row.names = FALSE)
###############################


################################################################################
# PART A: All Regions Processing
################################################################################

########## Shared Part A inputs ##########
# cf tables were already patched by patch_gcam_data() above (South Korea
# renewable CF overrides + Korea conventional CFs), so they are used as loaded.
# load_gcam_rda (modules/00_utils.R) picks the file matching version_number.
cf_rgn  <- load_gcam_rda("cf_rgn")
cf_gcam <- load_gcam_rda("cf_gcam")

# Generation by technology, shared by a2 (battery storage) and a3 (Gen III).
elec_gen <- getQuery(prj, "elec gen by gen tech")
##########################################

# a1: replace Price|Carbon rows from the "CO2 prices" query (skips if absent)
data <- add_carbon_price(data, prj)

# a2: build Capacity|...|Battery Storage rows from PV_storage / wind_storage
data <- add_battery_storage(data, elec_gen, cf_rgn)

# a3: add Gen_III_Korea to Primary Energy|Nuclear, then apply the 2.1x
# renewable primary energy multiplier (order matters: nuclear add first)
data <- add_gen3_nuclear(data, elec_gen)
data <- scale_renewable_primary(data)

# a4: recalculate Capacity|Electricity from vintage generation and correct
# CFs (gcamreport cf_iea bug fix; skips if the vintage query is absent)
data <- recalc_vintage_capacity(data, prj, cf_rgn, cf_gcam)

# a5: recompute parent capacity variables as the sum of their children
# (gcamreport double-counting bug fix; must run after a2/a4)
data <- enforce_capacity_consistency(data)

# a6: relabel High-Value Chemicals unit Mt/yr -> EJ/yr (gcamreport bug fix)
data <- fix_hvc_units(data)

########## Save All Regions Data ##########
csv_file <- file.path(output_dir, paste0(run_name, ".csv"))
data <- data %>% mutate(across(where(is.numeric), ~replace_na(., 0)))
write.csv(data, csv_file, row.names = FALSE)
cat("Saved all regions data:", csv_file, "\n")
#########################################


################################################################################
# PART B: Korea-Specific Processing
################################################################################

# Keep only target_region and years within [start_year, final_year].
# Every b* module below assumes this Korea-only, year-trimmed data.
data_korea <- filter_region_years(data, target_region, start_year, final_year)

# b1: redistribute aviation/shipping emissions by Korean domestic ratios and
# take international bunkers out of every total up to Emissions|{gas},
# including the Kyoto Gases (CO2eq) tree
data_korea <- reallocate_all_bunker_emissions(
  data_korea, gases = c("CO2", "N2O", "CH4", "Kyoto Gases"))

# b2: derive Primary Energy|...|Hydrogen and Primary Energy|Biomass|Electricity
# rows from Secondary Energy using GCAM coefficient files in kaist/data/
data_korea <- add_primary_from_secondary(data_korea)

# b3: split Iron and Steel coal into Fuel / Feedstock using technology-share
# weighted literature ratios (skips if the industry query is absent)
data_korea <- split_steel_coal(data_korea, prj)

# b4: convert transportation Energy Service (billion pkm/tkm) into thousand
# vehicles using MT 2020 reference vehicle counts; ref_scenario (config.R)
# anchors the conversion ratio, NULL falls back to the first scenario
data_korea <- add_vehicle_capacity(data_korea, ref_scenario)

# b5: split each sector's Liquids by the national biomass blend share --
# creates Final Energy|...|Biomass|Liquids rows AND scales the Liquids rows
# by (1 - share) so the biomass part is moved, not double-counted
data_korea <- split_biomass_liquids(data_korea)

########## Save Korea Data ##########
korea_output <- file.path(output_dir, paste0(run_name, "_korea.csv"))
data_korea <- data_korea %>% mutate(across(where(is.numeric), ~replace_na(., 0)))
write.csv(data_korea, korea_output, row.names = FALSE, fileEncoding = "UTF-8")

cat("\n=== Step 2 Complete ===\n")
cat("All regions:", csv_file, "\n")
cat("Korea only:", korea_output, "\n")
cat("Next: Run kaist/step3_create_mapping.R\n")
#########################################
