################################################################################
# a3: Gen_III_Korea nuclear addition + renewable primary energy fix
#
# 1. add_gen3_nuclear(): add Gen_III_Korea generation (a Korea-only tech that
#    gcamreport does not map) into Primary Energy|Nuclear.
# 2. scale_renewable_primary(): apply a 2.1x multiplier to renewable primary
#    energy (Solar, Wind, Hydro, Nuclear, Geothermal) in all regions, and
#    propagate the increase into the Primary Energy total.
#
# Run add_gen3_nuclear() BEFORE scale_renewable_primary(): the multiplier
# must also scale the nuclear generation added in step 1.
################################################################################

add_gen3_nuclear <- function(data, elec_gen) {
  # Convert tibble to data.frame for easier row assignment
  data <- as.data.frame(data)

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

  data
}

scale_renewable_primary <- function(data, factor = 2.1) {
  data <- as.data.frame(data)
  year_cols_data <- names(data)[grepl("^[0-9]{4}$", names(data))]

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

        # Apply multiplier to all matching rows
        data[all_rows, year_cols_data] <- data[all_rows, year_cols_data] * factor

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

  data
}
