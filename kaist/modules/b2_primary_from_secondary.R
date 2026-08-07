################################################################################
# b2: Calculate Primary Energy from Secondary Energy (Korea only)
#
# Creates Primary Energy|<fuel>|Hydrogen, Primary Energy|Electricity|Hydrogen
# and Primary Energy|Biomass|Electricity rows by dividing / multiplying
# Secondary Energy rows with GCAM technology coefficients:
#   - kaist/data/L225.GlobalTechCoef_h2.csv   (hydrogen production coefficients)
#   - kaist/data/L223.GlobalTechEff_elec.csv  (electricity generation efficiency)
#
# Rows whose source Secondary Energy variables are absent from the run are
# silently skipped (the loops simply produce nothing).
################################################################################

# Multiply a Secondary Energy row by the year-average coefficient -> new Variable
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

# Split total into CCS / non-CCS parts, apply separate coefficients, sum back
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

add_primary_from_secondary <- function(data, coef_dir = kaist_data_dir) {
  year_columns <- names(data)[grepl("^[0-9]{4}$", names(data))]

  h2_coef <- read.csv(file.path(coef_dir, "L225.GlobalTechCoef_h2.csv"),
                      skip = 1, stringsAsFactors = FALSE)
  elec_eff <- read.csv(file.path(coef_dir, "L223.GlobalTechEff_elec.csv"),
                       skip = 1, stringsAsFactors = FALSE)

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
    h2_total <- data %>% filter(Variable == paste0("Secondary Energy|Hydrogen|", source_info$fuel))
    h2_ccs <- data %>% filter(Variable == paste0("Secondary Energy|Hydrogen|", source_info$fuel, "|w/ CCS"))

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

  h2_elec <- data %>% filter(Variable == "Secondary Energy|Hydrogen|Electricity")
  elec_coef <- h2_coef %>%
    filter(technology == "electrolysis", minicam.energy.input == "elect_td_ind") %>%
    select(year, coefficient)
  result <- apply_coefficient_to_secondary(h2_elec, "Primary Energy|Electricity|Hydrogen", elec_coef, year_columns)
  primary_energy_list[[length(primary_energy_list) + 1]] <- result

  elec_biomass_ccs <- data %>% filter(Variable == "Secondary Energy|Electricity|Biomass|w/ CCS")
  elec_biomass_no_ccs <- data %>% filter(Variable == "Secondary Energy|Electricity|Biomass|w/o CCS")

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
  bind_rows(data, primary_energy_data)
}
