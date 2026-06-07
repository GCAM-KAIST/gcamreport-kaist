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

########## Update CO2 Prices ##########
# Skip if the .dat does not have the "CO2 prices" query (e.g. step1 was run
# with desired_variables restricted to Capacity / Emissions only).
co2_prices <- tryCatch(getQuery(prj, "CO2 prices"), error = function(e) NULL)

if (!is.null(co2_prices)) {
  regions_list <- unique(getQuery(prj, "CO2 emissions by region")$region)
  valid_markets <- paste0(regions_list, "CO2")

  co2_price_all <- co2_prices %>%
    filter(market %in% valid_markets) %>%
    select(scenario, market, year, value) %>%
    pivot_wider(names_from = year, values_from = value) %>%
    mutate(
      Model = model_name,
      Region = sub("CO2$", "", market),
      Variable = "Price|Carbon",
      Unit = "1990$/tC"
    ) %>%
    rename(Scenario = scenario) %>%
    select(Model, Scenario, Region, Variable, Unit, everything(), -market)

  data <- data %>%
    filter(Variable != "Price|Carbon") %>%
    bind_rows(co2_price_all)
} else {
  message("Skipping CO2 Prices update -- query not present in .dat.")
}
#########################################

########## Battery Storage Capacity ##########
load(file.path(getwd(), "data/cf_rgn_v7.0.rda"))
# cf_rgn_v7.0.rda was already patched by patch_gcam_data() above (South Korea
# renewable CF overrides + Korea conventional CFs), so it is used as loaded.

elec_gen <- getQuery(prj, "elec gen by gen tech")

storage_gen <- elec_gen %>%
  filter(technology %in% c("PV_storage", "wind_storage"))

cf_storage <- cf_rgn_v7.0 %>%
  filter(stub.technology %in% c("PV_storage", "wind_storage")) %>%
  select(region, technology = stub.technology, year, cf = capacity.factor)

battery_storage <- storage_gen %>%
  left_join(cf_storage, by = c("region", "technology", "year")) %>%
  mutate(battery_capacity_gw = (value / (cf * 8760)) * 1e9 / 3600) %>%
  select(scenario, region, subsector, technology, year, battery_capacity_gw) %>%
  pivot_wider(names_from = year, values_from = battery_capacity_gw) %>%
  mutate(
    Model = model_name,
    Region = region,
    Variable = case_when(
      technology == "PV_storage" ~ "Capacity|Electricity|Solar|PV|Battery Storage",
      technology == "wind_storage" ~ "Capacity|Electricity|Wind|Battery Storage"
    ),
    Unit = "GW"
  ) %>%
  rename(Scenario = scenario) %>%
  select(Model, Scenario, Region, Variable, Unit, everything(), -region, -subsector, -technology)

data <- data %>%
  filter(!grepl("Battery Storage", Variable)) %>%
  bind_rows(battery_storage)
#########################################

########## Gen_III_Korea and Renewable Primary Energy Fix ##########
# 1. Add Gen_III_Korea generation to Primary Energy|Nuclear
# 2. Apply 2.1x multiplier to renewable primary energy (all regions)
# 3. Add changes to Primary Energy

# Convert tibble to data.frame for easier row assignment
data <- as.data.frame(data)

gen3_korea_gen <- elec_gen %>%
  filter(technology == "Gen_III_Korea") %>%
  select(scenario, region, year, value)

# Year columns in data
year_cols_data <- names(data)[grepl("^[0-9]{4}$", names(data))]

# Step 1: Add Gen_III_Korea to Primary Energy|Nuclear
if (nrow(gen3_korea_gen) > 0) {
  gen3_korea_primary <- gen3_korea_gen %>%
    pivot_wider(names_from = year, values_from = value, values_fill = 0) %>%
    rename(Scenario = scenario, Region = region)

  year_cols <- setdiff(names(gen3_korea_primary), c("Scenario", "Region"))

  for (i in 1:nrow(data)) {
    if (data$Variable[i] == "Primary Energy|Nuclear") {
      match_idx <- which(
        gen3_korea_primary$Scenario == data$Scenario[i] &
        gen3_korea_primary$Region == data$Region[i]
      )
      if (length(match_idx) > 0) {
        for (year_col in year_cols) {
          if (year_col %in% names(data)) {
            data[i, year_col] <- as.numeric(data[i, year_col]) +
                                  as.numeric(gen3_korea_primary[match_idx[1], year_col])
          }
        }
      }
    }
  }
}

# Step 2 & 3: Apply 2.1x to renewable primary energy and update Primary Energy
renewable_sources <- c("Solar", "Wind", "Hydro", "Nuclear", "Geothermal")

# Get unique scenario-region combinations
scenario_regions <- data %>%
  select(Scenario, Region) %>%
  distinct()

for (sr_idx in 1:nrow(scenario_regions)) {
  scen <- scenario_regions$Scenario[sr_idx]
  reg <- scenario_regions$Region[sr_idx]

  # Find Primary Energy row for this scenario-region
  pe_row <- which(data$Variable == "Primary Energy" &
                  data$Scenario == scen &
                  data$Region == reg)

  total_increase <- numeric(length(year_cols_data))

  for (source in renewable_sources) {
    # Find top-level variable row
    top_var_name <- paste0("Primary Energy|", source)
    top_row <- which(data$Variable == top_var_name &
                     data$Scenario == scen &
                     data$Region == reg)

    # Find all rows including sub-variables
    pattern_all <- paste0("^Primary Energy\\|", source, ".*")
    all_rows <- which(grepl(pattern_all, data$Variable) &
                      data$Scenario == scen &
                      data$Region == reg)

    if (length(all_rows) > 0) {
      # Save original value of top-level variable
      if (length(top_row) > 0) {
        original_top <- as.numeric(data[top_row, year_cols_data])
      }

      # Apply 2.1x to all matching rows
      data[all_rows, year_cols_data] <- data[all_rows, year_cols_data] * 2.1

      # Calculate increase from top-level variable
      if (length(top_row) > 0) {
        new_top <- as.numeric(data[top_row, year_cols_data])
        total_increase <- total_increase + (new_top - original_top)
      }
    }
  }

  # Add total increase to Primary Energy
  total_increase[is.na(total_increase)] <- 0
  if (length(pe_row) > 0 && sum(abs(total_increase), na.rm = TRUE) > 0) {
    data[pe_row, year_cols_data] <- as.numeric(data[pe_row, year_cols_data]) + total_increase
  }
}
#########################################

########## Recalculate Capacity|Electricity using vintage-based calculation ##########
# gcamreport bug: cf_iea (from IEA world average) is used instead of cf_gcam/cf_rgn
#   - Renewables: cf_iea duplicates cf_rgn entries, causing averaging
#   - Fossil fuels: cf_iea (~50-60%) used instead of cf_gcam (80-85%)
#
# Fix: Recalculate Capacity using vintage-based generation data and correct CF values
#   - cf_rgn: Regional CF for renewables (wind, PV, CSP)
#   - cf_gcam: Default CF for nuclear (0.9), fossil fuels (0.8-0.85), etc.
#
# Method: For each vintage, Capacity = Generation / (CF * 8760 * conversion)
#         Then sum capacities across all vintages

# Load cf_gcam for technologies not in cf_rgn
load(file.path(getwd(), "data/cf_gcam_v7.0.rda"))

# Get vintage generation data from GCAM
elec_gen_vintage <- tryCatch({
  getQuery(prj, "elec gen by gen tech and cooling tech and vintage")
}, error = function(e) {
  cat("Warning: Could not load vintage query:", e$message, "\n")
  NULL
})

if (!is.null(elec_gen_vintage) && nrow(elec_gen_vintage) > 0) {
  cat("Loaded vintage generation data:", nrow(elec_gen_vintage), "rows\n")

  # Conversion constants
  EJ_to_GWh <- 3.6e-6
  hr_per_yr <- 8760

  # Technology to capacity variable mapping
  # Includes renewables, nuclear, and fossil fuels
  tech_to_cap <- tribble(
    ~tech_base,       ~cap_var,
    # Renewables
    "wind",           "Capacity|Electricity|Wind|Onshore",
    # "wind_storage",   "Capacity|Electricity|Wind|Onshore",  
    "wind_offshore",  "Capacity|Electricity|Wind|Offshore",
    "PV",             "Capacity|Electricity|Solar|PV",
    # "PV_storage",     "Capacity|Electricity|Solar|PV",      
    "rooftop_pv",     "Capacity|Electricity|Solar|PV",
    "CSP",            "Capacity|Electricity|Solar|CSP",
    # "CSP_storage",    "Capacity|Electricity|Solar|CSP",     
    # Nuclear
    "Gen_III",        "Capacity|Electricity|Nuclear",
    "Gen_III_Korea",  "Capacity|Electricity|Nuclear",
    "Gen_II_LWR",     "Capacity|Electricity|Nuclear",
    # Hydro & Geothermal
    "hydro",          "Capacity|Electricity|Hydro",
    "geothermal",     "Capacity|Electricity|Geothermal",
    # Coal (cf_gcam: 0.85 for conv pul, 0.80 for IGCC)
    "coal (conv pul)",     "Capacity|Electricity|Coal|w/o CCS",
    "coal (conv pul CCS)", "Capacity|Electricity|Coal|w/ CCS",
    "coal (IGCC)",         "Capacity|Electricity|Coal|w/o CCS",
    "coal (IGCC CCS)",     "Capacity|Electricity|Coal|w/ CCS",
    # Gas (cf_gcam: 0.85 for CC, 0.80 for steam/CT)
    "gas (CC)",            "Capacity|Electricity|Gas|w/o CCS",
    "gas (CC CCS)",        "Capacity|Electricity|Gas|w/ CCS",
    "gas (steam/CT)",      "Capacity|Electricity|Gas|w/o CCS",
    # Oil / Refined liquids (cf_gcam: 0.85 for CC, 0.80 for steam/CT)
    "refined liquids (CC)",      "Capacity|Electricity|Oil|w/o CCS",
    "refined liquids (CC CCS)",  "Capacity|Electricity|Oil|w/ CCS",
    "refined liquids (steam/CT)","Capacity|Electricity|Oil|w/o CCS",
    # Biomass (cf_gcam: 0.85 for conv, 0.80 for IGCC)
    "biomass (conv)",      "Capacity|Electricity|Biomass|w/o CCS",
    "biomass (conv CCS)",  "Capacity|Electricity|Biomass|w/ CCS",
    "biomass (IGCC)",      "Capacity|Electricity|Biomass|w/o CCS",
    "biomass (IGCC CCS)",  "Capacity|Electricity|Biomass|w/ CCS"
  )

  # Build CF lookup: cf_rgn has (region, technology, year) -> CF
  # For each vintage, use the CF from the year closest to vintage
  cf_rgn_lookup <- cf_rgn_v7.0 %>%
    select(region, technology = stub.technology, cf_year = year, cf = capacity.factor)

  cf_gcam_lookup <- cf_gcam_v7.0 %>%
    select(technology, cf_default = `2100`)

  # NOTE: Korea-specific CF overrides for conventional techs (coal, gas, oil,
  # hydro, nuclear, biomass, CSP) are NOT hard-coded here anymore. They live
  # in inst/extdata/saveDataFiles_GCAM7.0.R as additional South Korea rows in
  # cf_rgn_v7.0, so they are picked up automatically by cf_rgn_lookup above.
  # If you need to change a Korea CF value, edit saveDataFiles_GCAM7.0.R and
  # rerun it once to regenerate data/cf_rgn_v7.0.rda.

  # Process vintage data
  # Technology column format: "tech_name,year=vintage"
  #   e.g. "PV,year=2020", "biomass (IGCC CCS) (dry cooling),year=2030"
  # Extract tech_base by: removing ",year=..." then stripping cooling suffix " (cooling_type)"
  elec_gen_processed <- elec_gen_vintage %>%
    mutate(
      tech_full = sub(",year=.*", "", technology),
      vintage = as.integer(sub(".*,year=", "", technology)),
      tech_base = gsub(" \\(dry cooling\\)| \\(recirculating\\)| \\(once through\\)| \\(seawater\\)| \\(none\\)", "", tech_full)
    ) %>%
    # Sum by (scenario, region, tech_base, vintage, year) - combines cooling variants
    group_by(scenario, region, tech_base, vintage, year) %>%
    summarise(generation_EJ = sum(value, na.rm = TRUE), .groups = "drop")

  # Get CF for each (region, technology, vintage) combination
  # Use cf_rgn if available, otherwise cf_gcam
  capacity_by_vintage <- elec_gen_processed %>%
    # Join with cf_rgn - find closest year
    left_join(
      cf_rgn_lookup %>%
        group_by(region, technology) %>%
        summarise(cf = first(cf), .groups = "drop"),  # Use first CF (they're all same)
      by = c("region", "tech_base" = "technology")
    ) %>%
    # If no cf_rgn, fall back to cf_gcam global default
    left_join(cf_gcam_lookup, by = c("tech_base" = "technology")) %>%
    # CF priority: cf_rgn (per-region; includes Korea overrides from data
    # file) -> cf_gcam (global default)
    mutate(
      cf_final = coalesce(cf, cf_default),
      # Calculate capacity for this vintage: GW = EJ / (CF * 8760 * 3.6e-6)
      capacity_gw = ifelse(
        !is.na(cf_final) & cf_final > 0,
        generation_EJ / (cf_final * hr_per_yr * EJ_to_GWh),
        NA_real_
      )
    )

  # Sum capacity across vintages for each (scenario, region, tech_base, year)
  capacity_total <- capacity_by_vintage %>%
    group_by(scenario, region, tech_base, year) %>%
    summarise(
      capacity_gw = sum(capacity_gw, na.rm = TRUE),
      cf_used = first(cf_final),  # For debugging
      .groups = "drop"
    ) %>%
    # Map to capacity variable names
    left_join(tech_to_cap, by = "tech_base") %>%
    filter(!is.na(cap_var)) %>%
    # Aggregate by capacity variable (e.g., Gen_III + Gen_III_Korea -> Nuclear)
    group_by(scenario, region, cap_var, year) %>%
    summarise(capacity_gw = sum(capacity_gw, na.rm = TRUE), .groups = "drop")

  # Update data with recalculated capacity
  year_cols <- names(data)[grepl("^[0-9]{4}$", names(data))]

  for (cap_var in unique(capacity_total$cap_var)) {
    cap_new <- capacity_total %>% filter(cap_var == !!cap_var)

    for (j in 1:nrow(cap_new)) {
      scen <- cap_new$scenario[j]
      rgn <- cap_new$region[j]
      yr <- as.character(cap_new$year[j])
      new_val <- cap_new$capacity_gw[j]

      if (!yr %in% year_cols) next

      # Find matching row in data
      idx <- which(data$Variable == cap_var & data$Scenario == scen & data$Region == rgn)

      if (length(idx) > 0 && !is.na(new_val) && new_val > 0) {
        data[idx[1], yr] <- new_val
      }
    }
  }

  cat("Recalculated Capacity|Electricity using vintage-based calculation with correct CF\n")

  # Debug output: show CF and verify generation back-calculation for first scenario
  debug_scen <- capacity_by_vintage$scenario[1]

  cat("\n=== CF values used for South Korea (scenario:", debug_scen, ") ===\n")
  capacity_by_vintage %>%
    filter(region == "South Korea", year == 2050, scenario == debug_scen) %>%
    group_by(tech_base) %>%
    summarise(cf = first(cf_final), .groups = "drop") %>%
    filter(!is.na(cf)) %>%
    arrange(tech_base) %>%
    print()

  cat("\n=== Verification: Generation back-calculation (South Korea, 2050) ===\n")
  capacity_by_vintage %>%
    filter(region == "South Korea", year == 2050, scenario == debug_scen,
           !is.na(cf_final), cf_final > 0) %>%
    group_by(tech_base) %>%
    summarise(
      cf = first(cf_final),
      gen_original_EJ = sum(generation_EJ, na.rm = TRUE),
      capacity_GW = sum(capacity_gw, na.rm = TRUE),
      gen_backcalc_EJ = sum(capacity_gw, na.rm = TRUE) * first(cf_final) * hr_per_yr * EJ_to_GWh,
      .groups = "drop"
    ) %>%
    mutate(
      diff_pct = round((gen_backcalc_EJ - gen_original_EJ) / gen_original_EJ * 100, 4),
      match = ifelse(abs(diff_pct) < 0.01, "OK", "MISMATCH")
    ) %>%
    arrange(tech_base) %>%
    print(n = 30)

} else {
  cat("Skipped capacity recalculation (vintage query not available)\n")
}

########## Fix Parent-Child Capacity Consistency (gcamreport bug) ##########
# gcamreport bug: Parent capacity variables include double-counting
#   - Solar: elec_solar output counted separately from PV/PV_storage electricity output
#   - Wind: elec_wind output counted separately from wind/wind_storage electricity output
#   - Coal/Gas: similar issues with different tech variants
#
# Fix: Recalculate parent as sum of direct children
# This runs ALWAYS, regardless of whether vintage recalculation was available

year_cols_all <- names(data)[grepl("^[0-9]{4}$", names(data))]

# Define parent-child relationships
parent_children <- list(
  "Capacity|Electricity|Coal" = c("Capacity|Electricity|Coal|w/ CCS", "Capacity|Electricity|Coal|w/o CCS"),
  "Capacity|Electricity|Gas" = c("Capacity|Electricity|Gas|w/ CCS", "Capacity|Electricity|Gas|w/o CCS"),
  "Capacity|Electricity|Oil" = c("Capacity|Electricity|Oil|w/ CCS", "Capacity|Electricity|Oil|w/o CCS"),
  "Capacity|Electricity|Biomass" = c("Capacity|Electricity|Biomass|w/ CCS", "Capacity|Electricity|Biomass|w/o CCS"),
  "Capacity|Electricity|Solar" = c("Capacity|Electricity|Solar|PV", "Capacity|Electricity|Solar|CSP"),
  "Capacity|Electricity|Wind" = c("Capacity|Electricity|Wind|Onshore", "Capacity|Electricity|Wind|Offshore")
)

for (parent_var in names(parent_children)) {
  child_vars <- parent_children[[parent_var]]

  # Find child rows (exact match)
  child_idx <- which(data$Variable %in% child_vars)
  parent_idx <- which(data$Variable == parent_var)

  if (length(child_idx) > 0 && length(parent_idx) > 0) {
    # Sum children for each scenario and region
    for (scen in unique(data$Scenario[child_idx])) {
      for (rgn in unique(data$Region[child_idx])) {
        scen_child_idx <- child_idx[data$Scenario[child_idx] == scen & data$Region[child_idx] == rgn]
        scen_parent_idx <- parent_idx[data$Scenario[parent_idx] == scen & data$Region[parent_idx] == rgn]

        if (length(scen_parent_idx) > 0 && length(scen_child_idx) > 0) {
          child_sum <- colSums(data[scen_child_idx, year_cols_all, drop = FALSE], na.rm = TRUE)
          data[scen_parent_idx[1], year_cols_all] <- child_sum
        }
      }
    }
  }
}

# Update aggregate capacity variables
aggregate_parents <- list(
  "Capacity|Electricity|Fossil" = c("Capacity|Electricity|Coal", "Capacity|Electricity|Gas", "Capacity|Electricity|Oil"),
  "Capacity|Electricity|Non-Biomass Renewables" = c("Capacity|Electricity|Solar", "Capacity|Electricity|Wind",
                                                     "Capacity|Electricity|Hydro", "Capacity|Electricity|Geothermal")
)

for (parent_var in names(aggregate_parents)) {
  child_vars <- aggregate_parents[[parent_var]]
  child_idx <- which(data$Variable %in% child_vars)
  parent_idx <- which(data$Variable == parent_var)

  if (length(child_idx) > 0 && length(parent_idx) > 0) {
    for (scen in unique(data$Scenario)) {
      for (rgn in unique(data$Region)) {
        scen_child_idx <- child_idx[data$Scenario[child_idx] == scen & data$Region[child_idx] == rgn]
        scen_parent_idx <- parent_idx[data$Scenario[parent_idx] == scen & data$Region[parent_idx] == rgn]

        if (length(scen_parent_idx) > 0 && length(scen_child_idx) > 0) {
          child_sum <- colSums(data[scen_child_idx, year_cols_all, drop = FALSE], na.rm = TRUE)
          data[scen_parent_idx[1], year_cols_all] <- child_sum
        }
      }
    }
  }
}

cat("Fixed parent capacity variables (Coal, Gas, Oil, Biomass, Solar, Wind, Fossil, Non-Biomass Renewables)\n")
#########################################

########## Fix Production|Chemicals|High-Value Chemicals Unit (gcamreport bug) ##########
# gcamreport bug: EJ values are labeled as Mt/yr without conversion
# See: https://github.com/bc3LC/gcamreport - functions.R line 5752-5762
# The inner_join with template assigns Unit from template without converting values
#
# GCAM output units (from production_map):
#   - ammonia -> Mt NH3 (correct)
#   - chemical -> EJ (WRONG - labeled as Mt/yr in template)
#   - N fertilizer -> Mt N (correct)
#
# Fix: Change Unit from "Mt/yr" to "EJ/yr" for High-Value Chemicals only

hvc_idx <- which(data$Variable == "Production|Chemicals|High-Value Chemicals")
if (length(hvc_idx) > 0) {
  data[hvc_idx, "Unit"] <- "EJ/yr"
  cat("Fixed unit for Production|Chemicals|High-Value Chemicals: Mt/yr -> EJ/yr\n")
}
#########################################

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

########## Save Korea Data ##########
korea_output <- file.path(output_dir, paste0(run_name, "_korea.csv"))
data_korea <- data_korea %>% mutate(across(where(is.numeric), ~replace_na(., 0)))
write.csv(data_korea, korea_output, row.names = FALSE, fileEncoding = "UTF-8")

cat("\n=== Step 2 Complete ===\n")
cat("All regions:", csv_file, "\n")
cat("Korea only:", korea_output, "\n")
cat("Next: Run kaist/step3_create_mapping.R\n")
#########################################
