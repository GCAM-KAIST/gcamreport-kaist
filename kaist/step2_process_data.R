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
load(file.path(getwd(), "data/cf_rgn_v7.0.rda"))    # -> cf_rgn_v7.0
load(file.path(getwd(), "data/cf_gcam_v7.0.rda"))   # -> cf_gcam_v7.0

# Generation by technology, shared by a2 (battery storage) and a3 (Gen III).
elec_gen <- getQuery(prj, "elec gen by gen tech")
##########################################

# a1: replace Price|Carbon rows from the "CO2 prices" query (skips if absent)
data <- add_carbon_price(data, prj)

# a2: build Capacity|...|Battery Storage rows from PV_storage / wind_storage
data <- add_battery_storage(data, elec_gen, cf_rgn_v7.0)

# a3: add Gen_III_Korea to Primary Energy|Nuclear, then apply the 2.1x
# renewable primary energy multiplier (order matters: nuclear add first)
data <- add_gen3_nuclear(data, elec_gen)
data <- scale_renewable_primary(data)

# a4: recalculate Capacity|Electricity from vintage generation and correct
# CFs (gcamreport cf_iea bug fix; skips if the vintage query is absent)
data <- recalc_vintage_capacity(data, prj, cf_rgn_v7.0, cf_gcam_v7.0)

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

########## Filter Region and Year ##########
year_columns <- names(data)[grepl("^[0-9]{4}$", names(data))]
years_to_remove <- year_columns[as.numeric(year_columns) < start_year | as.numeric(year_columns) > final_year]
data_filtered <- data %>% select(-all_of(years_to_remove))

data_korea <- data_filtered %>% filter(Region == target_region)
data_korea <- as.data.frame(data_korea)  # Convert to data.frame for easier row assignment
year_columns <- names(data_korea)[grepl("^[0-9]{4}$", names(data_korea))]
#########################################

########## Reallocate Aviation and Shipping Emissions ##########
# Variable hierarchy (gcamreport structure):
#   Emissions|{gas}|Energy
#   ├── Demand                         ← includes Bunkers (international)
#   │   ├── Transportation             ← Domestic only (Aviation, Shipping, Bus, Rail...)
#   │   │   ├── Domestic Aviation
#   │   │   └── Domestic Shipping
#   │   ├── Bunkers                    ← International only
#   │   │   ├── International Aviation
#   │   │   └── International Shipping
#   │   └── Industry, Residential...
#   └── Supply
#
# What we do:
#   1. Redistribute Aviation/Shipping by Korean domestic ratios (9.3%, 3.2%)
#   2. Transportation += domestic change (Domestic values changed)
#   3. Bunkers += international change (International values changed)
#   4. Demand, Energy -= original international (exclude bunkers from totals)

min_year <- 2020
adj_year_cols <- year_columns[as.numeric(year_columns) >= min_year]

reallocate_bunker_emissions <- function(data, gas, adj_cols,
                                        aviation_dom_ratio = 0.093,
                                        shipping_dom_ratio = 0.032) {
  # Helper to get row index and values
  get_vals <- function(var) {
    idx <- which(data$Variable == paste0("Emissions|", gas, "|Energy|Demand|", var))
    if (length(idx) == 0) return(list(idx = NULL, vals = NULL))
    list(idx = idx, vals = as.numeric(unlist(data[idx, adj_cols])))
  }

  # Get all required variables
  dom_avi <- get_vals("Transportation|Domestic Aviation")
  intl_avi <- get_vals("Bunkers|International Aviation")
  dom_shp <- get_vals("Transportation|Domestic Shipping")
  intl_shp <- get_vals("Bunkers|International Shipping")

  if (is.null(dom_avi$idx) || is.null(intl_avi$idx) ||
      is.null(dom_shp$idx) || is.null(intl_shp$idx)) {
    cat("Warning: Missing variables for", gas, "\n")
    return(data)
  }

  # Redistribute
  total_avi <- dom_avi$vals + intl_avi$vals
  total_shp <- dom_shp$vals + intl_shp$vals

  new_dom_avi <- total_avi * aviation_dom_ratio
  new_intl_avi <- total_avi * (1 - aviation_dom_ratio)
  new_dom_shp <- total_shp * shipping_dom_ratio
  new_intl_shp <- total_shp * (1 - shipping_dom_ratio)

  # Changes
  dom_change <- (new_dom_avi - dom_avi$vals) + (new_dom_shp - dom_shp$vals)
  intl_change <- (new_intl_avi - intl_avi$vals) + (new_intl_shp - intl_shp$vals)
  old_intl_total <- intl_avi$vals + intl_shp$vals

  # Update values
  data[dom_avi$idx, adj_cols] <- new_dom_avi
  data[intl_avi$idx, adj_cols] <- new_intl_avi
  data[dom_shp$idx, adj_cols] <- new_dom_shp
  data[intl_shp$idx, adj_cols] <- new_intl_shp

  # Update parent variables
  for (var in c("Transportation", "Bunkers", "Demand", "")) {
    full_var <- paste0("Emissions|", gas, "|Energy|Demand")
    if (var != "") full_var <- paste0(full_var, "|", var)
    if (var == "") full_var <- paste0("Emissions|", gas, "|Energy")

    idx <- which(data$Variable == full_var)
    if (length(idx) == 0) next

    adj <- switch(var,
      "Transportation" = dom_change,
      "Bunkers" = intl_change,
      dom_change - old_intl_total  # Demand and Energy: exclude international
    )
    data[idx, adj_cols] <- as.numeric(unlist(data[idx, adj_cols])) + adj
  }

  cat("Reallocated", gas, ": dom_change =", round(sum(dom_change), 2),
      ", removed intl =", round(sum(old_intl_total), 2), "\n")
  data
}

for (gas in c("CO2", "N2O", "CH4")) {
  data_korea <- reallocate_bunker_emissions(data_korea, gas, adj_year_cols)
}
#########################################

########## Calculate Primary Energy from Secondary Energy ##########
h2_coef <- read.csv(file.path(kaist_data_dir, "L225.GlobalTechCoef_h2.csv"),
                    skip = 1, stringsAsFactors = FALSE)
elec_eff <- read.csv(file.path(kaist_data_dir, "L223.GlobalTechEff_elec.csv"),
                     skip = 1, stringsAsFactors = FALSE)

apply_coefficient_to_secondary <- function(source_data, new_variable_name, coefficient_data, year_cols) {
  if (nrow(source_data) == 0) return(NULL)
  result_list <- list()
  for (scen in unique(source_data$Scenario)) {
    new_row <- source_data %>% filter(Scenario == scen)
    for (year_col in year_cols) {
      year_val <- as.numeric(year_col)
      coef_val <- coefficient_data %>%
        filter(year == year_val) %>%
        summarise(avg = mean(coefficient, na.rm = TRUE)) %>%
        pull(avg)
      new_row[[year_col]] <- new_row[[year_col]] * coef_val
    }
    new_row$Variable <- new_variable_name
    result_list[[length(result_list) + 1]] <- new_row
  }
  bind_rows(result_list)
}

calculate_primary_with_ccs_split <- function(total_data, ccs_data, new_variable_name,
                                              coef_ccs, coef_no_ccs, year_cols) {
  if (nrow(total_data) == 0 || nrow(ccs_data) == 0) return(NULL)
  no_ccs_data <- total_data
  for (scen in unique(total_data$Scenario)) {
    total_row <- total_data %>% filter(Scenario == scen)
    ccs_row <- ccs_data %>% filter(Scenario == scen)
    no_ccs_row_idx <- which(no_ccs_data$Scenario == scen)
    no_ccs_data[no_ccs_row_idx, year_cols] <- total_row[, year_cols] - ccs_row[, year_cols]
  }
  primary_ccs <- apply_coefficient_to_secondary(ccs_data, new_variable_name, coef_ccs, year_cols)
  primary_no_ccs <- apply_coefficient_to_secondary(no_ccs_data, new_variable_name, coef_no_ccs, year_cols)
  result <- primary_ccs
  for (scen in unique(result$Scenario)) {
    ccs_idx <- which(result$Scenario == scen)
    no_ccs_row <- primary_no_ccs %>% filter(Scenario == scen)
    result[ccs_idx, year_cols] <- result[ccs_idx, year_cols] + no_ccs_row[, year_cols]
  }
  result
}

primary_energy_list <- list()

h2_sources <- list(
  biomass = list(fuel = "Biomass", input = "regional biomass",
                 tech_ccs = "biomass to H2 CCS", tech_no_ccs = "biomass to H2"),
  coal = list(fuel = "Coal", input = "regional coal",
              tech_ccs = "coal chemical CCS", tech_no_ccs = "coal chemical"),
  gas = list(fuel = "Gas", input = "regional natural gas",
             tech_ccs = c("natural gas steam reforming CCS", "gas ATR CCS"),
             tech_no_ccs = "natural gas steam reforming")
)

for (source_name in names(h2_sources)) {
  source_info <- h2_sources[[source_name]]
  h2_total <- data_korea %>% filter(Variable == paste0("Secondary Energy|Hydrogen|", source_info$fuel))
  h2_ccs <- data_korea %>% filter(Variable == paste0("Secondary Energy|Hydrogen|", source_info$fuel, "|w/ CCS"))

  coef_ccs <- h2_coef %>%
    filter(technology %in% source_info$tech_ccs, minicam.energy.input == source_info$input) %>%
    select(year, coefficient)
  coef_no_ccs <- h2_coef %>%
    filter(technology == source_info$tech_no_ccs, minicam.energy.input == source_info$input) %>%
    select(year, coefficient)

  if (nrow(h2_ccs) > 0) {
    result <- calculate_primary_with_ccs_split(h2_total, h2_ccs,
                paste0("Primary Energy|", source_info$fuel, "|Hydrogen"),
                coef_ccs, coef_no_ccs, year_columns)
  } else {
    result <- apply_coefficient_to_secondary(h2_total,
                paste0("Primary Energy|", source_info$fuel, "|Hydrogen"),
                coef_no_ccs, year_columns)
  }
  primary_energy_list[[length(primary_energy_list) + 1]] <- result
}

h2_elec <- data_korea %>% filter(Variable == "Secondary Energy|Hydrogen|Electricity")
elec_coef <- h2_coef %>%
  filter(technology == "electrolysis", minicam.energy.input == "elect_td_ind") %>%
  select(year, coefficient)
result <- apply_coefficient_to_secondary(h2_elec, "Primary Energy|Electricity|Hydrogen", elec_coef, year_columns)
primary_energy_list[[length(primary_energy_list) + 1]] <- result

elec_biomass_ccs <- data_korea %>% filter(Variable == "Secondary Energy|Electricity|Biomass|w/ CCS")
elec_biomass_no_ccs <- data_korea %>% filter(Variable == "Secondary Energy|Electricity|Biomass|w/o CCS")

biomass_eff_ccs <- elec_eff %>%
  filter(grepl("biomass", technology, ignore.case = TRUE),
         grepl("CCS", technology, ignore.case = TRUE),
         minicam.energy.input == "regional biomass") %>%
  select(year, efficiency)

biomass_eff_no_ccs <- elec_eff %>%
  filter(grepl("biomass", technology, ignore.case = TRUE),
         !grepl("CCS", technology, ignore.case = TRUE),
         minicam.energy.input == "regional biomass") %>%
  select(year, efficiency)

for (scen in unique(elec_biomass_ccs$Scenario)) {
  ccs_row <- elec_biomass_ccs %>% filter(Scenario == scen)
  no_ccs_row <- elec_biomass_no_ccs %>% filter(Scenario == scen)
  new_row <- ccs_row

  for (year_col in year_columns) {
    year_val <- as.numeric(year_col)
    eff_ccs <- biomass_eff_ccs %>% filter(year == year_val) %>%
      summarise(avg = mean(efficiency, na.rm = TRUE)) %>% pull(avg)
    eff_no_ccs <- biomass_eff_no_ccs %>% filter(year == year_val) %>%
      summarise(avg = mean(efficiency, na.rm = TRUE)) %>% pull(avg)
    new_row[[year_col]] <- ccs_row[[year_col]] / eff_ccs + no_ccs_row[[year_col]] / eff_no_ccs
  }

  new_row$Variable <- "Primary Energy|Biomass|Electricity"
  primary_energy_list[[length(primary_energy_list) + 1]] <- new_row
}

primary_energy_data <- bind_rows(primary_energy_list)
data_korea <- bind_rows(data_korea, primary_energy_data)
#########################################

########## Coal Feedstock/Fuel Split for Iron and Steel (Query-based) ##########
# GCAM doesn't distinguish coal feedstock vs fuel at subsector level.
# Use technology-specific ratios based on steel industry literature:
#   - BF (Blast Furnace): 75% feedstock (coke for reduction), 25% fuel (PCI)
#   - BF with H2: 50% feedstock (H2 partially replaces coke), 50% fuel
#   - BF CCS: 75% feedstock, 25% fuel (same as BF)
#   - EAF: 0% feedstock (coal only for heating)
# Data source: "industry final energy by tech and fuel" query from .prj file

cat("\n=== Coal Feedstock/Fuel Split for Iron and Steel (Query-based) ===\n")

is_energy <- tryCatch({
  getQuery(prj, "industry final energy by tech and fuel") %>%
    filter(grepl("iron", sector, ignore.case = TRUE),
           region == target_region,
           grepl("coal", input, ignore.case = TRUE))
}, error = function(e) {
  cat("Warning: Could not load 'industry final energy by tech and fuel':", e$message, "\n")
  NULL
})

if (!is.null(is_energy) && nrow(is_energy) > 0) {
  # Technology-specific feedstock ratios (literature-based)
  tech_fs_ratio <- c(
    "BLASTFUR" = 0.75,
    "BLASTFUR CCS" = 0.75,
    "BLASTFUR with hydrogen" = 0.50,
    "EAF with DRI" = 0,
    "EAF with DRI CCS" = 0
  )

  # Calculate coal use by technology and scenario
  coal_by_tech <- is_energy %>%
    group_by(scenario, technology, year) %>%
    summarise(value = sum(value, na.rm = TRUE), .groups = "drop")

  # Log technologies found (for debugging)
  cat("Technologies found:", paste(unique(coal_by_tech$technology), collapse = ", "), "\n")

  # Calculate weighted feedstock/fuel ratios per scenario and year
  coal_ratios <- coal_by_tech %>%
    mutate(
      fs_ratio = tech_fs_ratio[technology],
      fs_ratio = ifelse(is.na(fs_ratio), 0, fs_ratio),
      feedstock = value * fs_ratio,
      fuel = value * (1 - fs_ratio)
    ) %>%
    group_by(scenario, year) %>%
    summarise(
      total_coal = sum(value, na.rm = TRUE),
      feedstock_total = sum(feedstock, na.rm = TRUE),
      fuel_total = sum(fuel, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      feedstock_ratio = ifelse(total_coal > 0, feedstock_total / total_coal, 0),
      fuel_ratio = ifelse(total_coal > 0, fuel_total / total_coal, 0)
    )

  cat("Feedstock/Fuel ratios by scenario and year:\n")
  print(coal_ratios %>%
    filter(year %in% seq(2020, 2050, 5)) %>%
    select(scenario, year, feedstock_ratio, fuel_ratio))

  # Split Iron and Steel Coal into Fuel and Feedstock
  is_coal_var <- "Final Energy|Industry|Iron and Steel|Solids|Coal"

  for (scen in unique(coal_ratios$scenario)) {
    is_coal_idx <- which(data_korea$Variable == is_coal_var & data_korea$Scenario == scen)
    if (length(is_coal_idx) == 0) next

    fuel_row <- data_korea[is_coal_idx[1], ]
    fuel_row$Variable <- "Final Energy|Industry|Iron and Steel|Coal|Fuel"

    feed_row <- data_korea[is_coal_idx[1], ]
    feed_row$Variable <- "Final Energy|Industry|Iron and Steel|Coal|Feedstock"

    for (yr_col in year_columns) {
      yr <- as.numeric(yr_col)
      ratio_row <- coal_ratios %>% filter(scenario == scen, year == yr)
      total_val <- as.numeric(data_korea[is_coal_idx[1], yr_col])
      if (nrow(ratio_row) > 0 && !is.na(total_val)) {
        fuel_row[[yr_col]] <- total_val * ratio_row$fuel_ratio[1]
        feed_row[[yr_col]] <- total_val * ratio_row$feedstock_ratio[1]
      } else {
        fuel_row[[yr_col]] <- total_val  # Default: treat as all fuel
        feed_row[[yr_col]] <- 0
      }
    }

    data_korea <- rbind(data_korea, fuel_row, feed_row)
  }

  cat("Created Iron and Steel Coal Fuel/Feedstock split variables\n")
} else {
  cat("Skipped Iron and Steel coal feedstock split (query not available)\n")
}
#########################################

########## Convert Energy Service to Vehicle Capacity (thousand vehicles) ##########
# Convert transportation Energy Service (billion pkm/tkm) to vehicle counts
# Method: Use MT 2020 reference vehicle counts to derive a fixed conversion ratio
#         Ratio = MT_2020_total_vehicles / GCAM_2020_energy_service_total
#         Then apply this ratio to all years for each sub-category
#
# Note: GCAM "Plug-in Hybrid" corresponds to MT "Hybrid Liquids" → template "HEV"
#       This renaming is handled in the mapping template (step3), not here.

# MT 2020 reference vehicle counts (thousand vehicles, from MT nzM_Adv scenario)
mt_ldv_2020 <- list(
  BEV  = 37.10865787,
  FCEV = 0.903601319,
  HEV  = 528.2116506,   # = Plug-in Hybrid in gcamreport
  ICEV = 19415.05747,
  PHEV = 0
)
mt_mhdv_2020 <- list(
  BEV  = 13.93759524,
  FCEV = 0,
  HEV  = 0,
  ICEV = 4512.069043,
  PHEV = 0
)

mt_ldv_total <- sum(unlist(mt_ldv_2020))   # 19981.28
mt_mhdv_total <- sum(unlist(mt_mhdv_2020)) # 4526.01

# Energy Service variables to convert
ldv_vars <- c(
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle",
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Battery-Electric",
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Fuel-Cell-Electric",
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Internal Combustion",
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Plug-in Hybrid"
)

mhdv_vars <- c(
  "Energy Service|Transportation|Freight|Truck",
  "Energy Service|Transportation|Freight|Truck|Battery-Electric",
  "Energy Service|Transportation|Freight|Truck|Internal Combustion",
  "Energy Service|Transportation|Freight|Truck|Plug-in Hybrid"
)

cat("\n=== Converting Energy Service to Vehicle Capacity ===\n")

# Compute ratios from reference scenario's 2020 values (used for ALL scenarios)
# ref_scenario can be set in config.R; defaults to first available scenario
if (exists("ref_scenario")) {
  ref_scen <- ref_scenario
} else {
  ref_scen <- unique(data_korea$Scenario)[1]
  cat(sprintf("  No ref_scenario in config.R, using first scenario: %s\n", ref_scen))
}

ldv_ref_idx <- which(data_korea$Variable == ldv_vars[1] & data_korea$Scenario == ref_scen)
mhdv_ref_idx <- which(data_korea$Variable == mhdv_vars[1] & data_korea$Scenario == ref_scen)

ldv_ratio <- mt_ldv_total / as.numeric(data_korea[ldv_ref_idx[1], "2020"])
mhdv_ratio <- mt_mhdv_total / as.numeric(data_korea[mhdv_ref_idx[1], "2020"])

cat(sprintf("  LDV ratio (from %s): %.4f (thousand vehicles / billion pkm)\n", ref_scen, ldv_ratio))
cat(sprintf("  MHDV ratio (from %s): %.4f (thousand vehicles / billion tkm)\n", ref_scen, mhdv_ratio))

# Apply ratios to all scenarios
for (var in ldv_vars) {
  var_idx <- which(data_korea$Variable == var)
  if (length(var_idx) > 0) {
    data_korea[var_idx, year_columns] <- data_korea[var_idx, year_columns] * ldv_ratio
    data_korea[var_idx, "Unit"] <- "thousand vehicles"
  }
}

for (var in mhdv_vars) {
  var_idx <- which(data_korea$Variable == var)
  if (length(var_idx) > 0) {
    data_korea[var_idx, year_columns] <- data_korea[var_idx, year_columns] * mhdv_ratio
    data_korea[var_idx, "Unit"] <- "thousand vehicles"
  }
}
#########################################

########## Biomass Origin Split for Final Energy Liquids (National Blend-Share Allocation) ##########
# GCAM blends all liquid fuel production (oil refining + biomass liquids +
# coal-to-liquids + gas-to-liquids) into a single "refining" market before
# any final-demand sector consumes it, so gcamreport has no
# "Final Energy|<sector>|...|Biomass|Liquids" variable under any name --
# final_energy_map.csv never gives "refined liquids" a biomass branch.
# See kmip/oil/biomass_liquids_reporting_gap.md for the full trace.
#
# This is not just an approximation: every South Korea final-demand sector
# draws 100% of its liquid fuel from this one domestic blended pool. The
# global technology definitions for "refined liquids enduse" and
# "refined liquids industrial" (en_distribution.xml) have exactly one
# energy input, "refining", at efficiency = 1, in every modeled period,
# with no market-name override -- there is no import path that bypasses
# the domestic blend. Because the pool is homogeneous, the national
# biomass share of total refining output equals the biomass share of ANY
# sector's liquid fuel consumption -- an exact decomposition, not a
# modeling assumption:
#   Final Energy|<sector>|Biomass|Liquids =
#     Final Energy|<sector>|Liquids * (Secondary Energy|Liquids|Biomass / Secondary Energy|Liquids)
#
# KMIP sector labels don't always match GCAM's own sector names 1:1 (e.g.
# KMIP "Road" = GCAM "Bus", KMIP "Ship" = GCAM "Domestic Shipping"); the
# correspondence below was verified against gcam_available_variables.csv
# and the existing (human-reviewed) mapping_template.xlsx rows for the
# same sectors under other fuel types (Coal/Electricity/Gases/Hydrogen).

cat("\n=== Biomass Origin Split for Final Energy Liquids (National Blend-Share) ===\n")

# se = Secondary Energy (supply side, where GCAM still tracks biomass origin)
se_liquids_total <- data_korea %>% filter(Variable == "Secondary Energy|Liquids")
se_liquids_bio   <- data_korea %>% filter(Variable == "Secondary Energy|Liquids|Biomass")

if (nrow(se_liquids_total) > 0 && nrow(se_liquids_bio) > 0) {

  # Step 1: biomass_share(scenario, year) =
  #   Secondary Energy|Liquids|Biomass / Secondary Energy|Liquids
  # One row per scenario x year, computed once here and reused for every
  # sector in Step 3 below -- this table IS the "national blend share".
  biomass_share <- se_liquids_total %>%
    select(Scenario, all_of(year_columns)) %>%
    pivot_longer(all_of(year_columns), names_to = "year", values_to = "se_liquids") %>%
    left_join(
      se_liquids_bio %>%
        select(Scenario, all_of(year_columns)) %>%
        pivot_longer(all_of(year_columns), names_to = "year", values_to = "se_liquids_bio"),
      by = c("Scenario", "year")
    ) %>%
    mutate(
      biomass_share = ifelse(!is.na(se_liquids) & se_liquids > 0,
                             se_liquids_bio / se_liquids, 0)
    )

  cat("biomass_share = Secondary Energy|Liquids|Biomass / Secondary Energy|Liquids:\n")
  print(biomass_share %>%
    filter(year %in% as.character(seq(2020, 2050, 5))) %>%
    select(Scenario, year, biomass_share))

  # Step 2: template_variable = exact KMIP name to create (including the KMIP
  # template's own "biomass" lowercase typo on the Other Sector row, so
  # step3's exact-match join picks it up as-is)
  # source_variable   = GCAM variable to allocate using biomass_share
  #   - Non-Metallic Minerals uses the Cement variant: GCAM has no
  #     separate non-Cement Non-Metallic Minerals liquids variable
  #   - Direct Air Capture is deliberately absent here: GCAM has no
  #     Final Energy|Direct Air Capture|Liquids variable at all (DAC only
  #     consumes Electricity/Gases), so its correct value is a hard 0,
  #     added separately below rather than allocated
  biomass_liquids_targets <- tribble(
    ~template_variable,                                           ~source_variable,
    "Final Energy|Industry|Biomass|Liquids",                      "Final Energy|Industry|Liquids",
    "Final Energy|Industry|Chemicals|Biomass|Liquids",             "Final Energy|Industry|Chemicals|Liquids",
    "Final Energy|Industry|Iron and Steel|Biomass|Liquids",        "Final Energy|Industry|Iron and Steel|Liquids",
    "Final Energy|Industry|Non-Metallic Minerals|Biomass|Liquids", "Final Energy|Industry|Non-Metallic Minerals|Cement|Liquids",
    "Final Energy|Industry|Other Sector|biomass|Liquids",          "Final Energy|Industry|Other Sector|Liquids",
    "Final Energy|Transportation|Biomass|Liquids",                 "Final Energy|Transportation|Liquids",
    "Final Energy|Transportation|Road|Biomass|Liquids",            "Final Energy|Transportation|Bus|Liquids",
    "Final Energy|Transportation|Rail|Biomass|Liquids",            "Final Energy|Transportation|Rail|Liquids",
    "Final Energy|Transportation|Ship|Biomass|Liquids",            "Final Energy|Transportation|Domestic Shipping|Liquids",
    "Final Energy|Transportation|Air|Biomass|Liquids",             "Final Energy|Transportation|Domestic Aviation|Liquids",
    "Final Energy|Building|Biomass|Liquids",                       "Final Energy|Residential and Commercial|Liquids",
    "Final Energy|Building|Residential|Biomass|Liquids",           "Final Energy|Residential|Liquids",
    "Final Energy|Building|Commercial/Public|Biomass|Liquids",     "Final Energy|Commercial|Liquids",
    "Final Energy|AFOFI|Biomass|Liquids",                          "Final Energy|Agriculture|Liquids"
  )

  # Step 3: for every (target sector, scenario), pull the GCAM source row
  # and multiply it, year by year, by that scenario's biomass_share from
  # the table built in Step 1.
  biomass_liquids_rows <- list()

  for (i in seq_len(nrow(biomass_liquids_targets))) {
    tgt_var <- biomass_liquids_targets$template_variable[i]
    src_var <- biomass_liquids_targets$source_variable[i]

    for (scen in unique(data_korea$Scenario)) {
      src_row <- data_korea %>% filter(Variable == src_var, Scenario == scen)
      scen_share <- biomass_share %>% filter(Scenario == scen)
      if (nrow(src_row) == 0 || nrow(scen_share) == 0) next

      new_row <- src_row[1, ]
      new_row$Variable <- tgt_var
      for (yr in year_columns) {
        share <- scen_share$biomass_share[scen_share$year == yr]
        new_row[[yr]] <- as.numeric(src_row[[yr]][1]) * share
      }
      biomass_liquids_rows[[length(biomass_liquids_rows) + 1]] <- new_row
    }
  }

  # Direct Air Capture: GCAM has no Liquids final-energy variable for this
  # sector at all, so its Biomass|Liquids value is a hard 0, not an
  # allocation -- added directly instead of via biomass_liquids_targets
  for (scen in unique(data_korea$Scenario)) {
    dac_row <- data_korea %>% filter(Variable == "Final Energy|Industry|Liquids", Scenario == scen)
    if (nrow(dac_row) == 0) next
    new_row <- dac_row[1, ]
    new_row$Variable <- "Final Energy|Direct Air Capture|Biomass|Liquids"
    new_row[, year_columns] <- 0
    biomass_liquids_rows[[length(biomass_liquids_rows) + 1]] <- new_row
  }

  if (length(biomass_liquids_rows) > 0) {
    data_korea <- rbind(data_korea, bind_rows(biomass_liquids_rows))
    cat("Created", length(biomass_liquids_rows),
        "Final Energy|...|Biomass|Liquids rows via national blend-share allocation\n")
  }
} else {
  cat("Skipped Biomass|Liquids allocation -- Secondary Energy|Liquids(|Biomass)",
      "not present in this run's queried variables\n")
}
#########################################

########## Save Korea Data ##########
korea_output <- file.path(output_dir, paste0(run_name, "_korea.csv"))
data_korea <- data_korea %>% mutate(across(where(is.numeric), ~replace_na(., 0)))
write.csv(data_korea, korea_output, row.names = FALSE, fileEncoding = "UTF-8")

cat("\n=== Step 2 Complete ===\n")
cat("All regions:", csv_file, "\n")
cat("Korea only:", korea_output, "\n")
cat("Next: Run kaist/step3_create_mapping.R\n")
#########################################
