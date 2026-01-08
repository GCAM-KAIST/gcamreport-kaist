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
#   - {output_prefix}.csv: Updated data for all regions
#   - {output_prefix}_korea.csv: Korea data with additional calculations
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
prj_files <- list.files(project_dir, pattern = "^project_.*\\.dat$", full.names = TRUE)
if (length(prj_files) > 0) {
  prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
  cat("Using project file:", basename(prj_file), "\n")
} else {
  stop("No project file found. Run step1_generate_report.R first.")
}
#########################################

########## Libraries ##########
devtools::load_all(".", reset = TRUE)
library(dplyr)
library(tidyr)
library(readxl)
library(rgcam)
################################

########## Load Data ##########
excel_file <- file.path(output_dir, paste0(output_prefix, ".xlsx"))
data <- read_excel(excel_file)

prj <- loadProject(prj_file)

gcam_vars <- available_variables_with_units(print = FALSE, GCAM_version = paste0("v", version_number))
write.csv(gcam_vars, file.path(output_dir, "gcam_available_variables.csv"), row.names = FALSE)
###############################


################################################################################
# PART A: All Regions Processing
################################################################################

########## Update CO2 Prices ##########
co2_prices <- getQuery(prj, "CO2 prices")
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
#########################################

########## Battery Storage Capacity ##########
load(file.path(getwd(), "data/cf_rgn_v7.0.rda"))

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

########## Gen_III_Korea Primary Energy Fix ##########
gen3_korea_gen <- elec_gen %>%
  filter(technology == "Gen_III_Korea") %>%
  select(scenario, region, year, value)

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
#########################################

########## Save All Regions Data ##########
csv_file <- file.path(output_dir, paste0(output_prefix, ".csv"))
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
year_columns <- names(data_korea)[grepl("^[0-9]{4}$", names(data_korea))]
#########################################

########## Reallocate Aviation and Shipping Emissions ##########
min_year <- 2020
adj_year_cols <- year_columns[as.numeric(year_columns) >= min_year]

aviation_domestic_ratio <- 0.093
aviation_international_ratio <- 1 - aviation_domestic_ratio
shipping_domestic_ratio <- 0.032
shipping_international_ratio <- 1 - shipping_domestic_ratio

reallocate_emissions <- function(data, gas, transport_type, domestic_ratio, international_ratio, year_cols_to_adjust) {
  var_domestic <- paste0("Emissions|", gas, "|Energy|Demand|Transportation|Domestic ", transport_type)
  var_international <- paste0("Emissions|", gas, "|Energy|Demand|Bunkers|International ", transport_type)

  domestic_data <- data %>% filter(Variable == var_domestic)
  international_data <- data %>% filter(Variable == var_international)

  if (length(year_cols_to_adjust) > 0 && nrow(domestic_data) > 0 && nrow(international_data) > 0) {
    total_data <- domestic_data
    total_data[, year_cols_to_adjust] <- domestic_data[, year_cols_to_adjust] + international_data[, year_cols_to_adjust]
    domestic_data[, year_cols_to_adjust] <- total_data[, year_cols_to_adjust] * domestic_ratio
    international_data[, year_cols_to_adjust] <- total_data[, year_cols_to_adjust] * international_ratio
    data <- data %>%
      filter(Variable != var_domestic & Variable != var_international) %>%
      bind_rows(domestic_data, international_data)
  }
  return(data)
}

for (gas in c("CO2", "N2O")) {
  data_korea <- reallocate_emissions(data_korea, gas, "Aviation",
                                      aviation_domestic_ratio, aviation_international_ratio, adj_year_cols)
  data_korea <- reallocate_emissions(data_korea, gas, "Shipping",
                                      shipping_domestic_ratio, shipping_international_ratio, adj_year_cols)
}
#########################################

########## Adjust Primary Energy for Renewables ##########
renewable_sources <- c("Solar", "Wind", "Hydro", "Nuclear", "Geothermal")

for (source in renewable_sources) {
  pattern <- paste0("^Primary Energy\\|", source, ".*")
  matching_rows <- grepl(pattern, data_korea$Variable)
  if (any(matching_rows)) {
    data_korea[matching_rows, year_columns] <- data_korea[matching_rows, year_columns] * 2.1
  }
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

########## Save Korea Data ##########
korea_output <- file.path(output_dir, paste0(output_prefix, "_korea.csv"))
write.csv(data_korea, korea_output, row.names = FALSE, fileEncoding = "UTF-8")

cat("\n=== Step 2 Complete ===\n")
cat("All regions:", csv_file, "\n")
cat("Korea only:", korea_output, "\n")
cat("Next: Run kaist/step3_create_mapping.R\n")
#########################################
