################################################################################
# a5: Fix parent-child capacity consistency
#
# gcamreport bug: Parent capacity variables include double-counting
#   - Solar: elec_solar output counted separately from PV/PV_storage electricity output
#   - Wind: elec_wind output counted separately from wind/wind_storage electricity output
#   - Coal/Gas: similar issues with different tech variants
#
# Fix: Recalculate parent as sum of direct children.
# Runs ALWAYS, regardless of whether vintage recalculation (a4) was available.
# Must run AFTER every module that adds or changes capacity child rows
# (a2 battery storage, a4 vintage recalculation).
################################################################################

enforce_capacity_consistency <- function(data) {
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

  data
}
