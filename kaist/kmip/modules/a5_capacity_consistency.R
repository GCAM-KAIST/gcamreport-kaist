################################################################################
# a5: Fix parent-child capacity consistency
#
# gcamreport bug: Parent capacity variables include double-counting
#   - Solar: elec_solar output counted separately from PV/PV_storage electricity output
#   - Wind: elec_wind output counted separately from wind/wind_storage electricity output
#   - Coal/Gas: similar issues with different tech variants
#
# Fix: Recalculate parent as sum of direct children
# (sum_children_into_parents in modules/00_utils.R does the actual summing).
# Runs ALWAYS, regardless of whether vintage recalculation (a4) was available.
# Must run AFTER every module that adds or changes capacity child rows
# (a2 battery storage, a4 vintage recalculation).
################################################################################

enforce_capacity_consistency <- function(data) {
  # Level 1: fuel parents from their w/ CCS / w/o CCS (or Onshore/Offshore,
  # PV/CSP) children
  parent_children <- list(
    "Capacity|Electricity|Coal" = c("Capacity|Electricity|Coal|w/ CCS", "Capacity|Electricity|Coal|w/o CCS"),
    "Capacity|Electricity|Gas" = c("Capacity|Electricity|Gas|w/ CCS", "Capacity|Electricity|Gas|w/o CCS"),
    "Capacity|Electricity|Oil" = c("Capacity|Electricity|Oil|w/ CCS", "Capacity|Electricity|Oil|w/o CCS"),
    "Capacity|Electricity|Biomass" = c("Capacity|Electricity|Biomass|w/ CCS", "Capacity|Electricity|Biomass|w/o CCS"),
    "Capacity|Electricity|Solar" = c("Capacity|Electricity|Solar|PV", "Capacity|Electricity|Solar|CSP"),
    "Capacity|Electricity|Wind" = c("Capacity|Electricity|Wind|Onshore", "Capacity|Electricity|Wind|Offshore")
  )
  data <- sum_children_into_parents(data, parent_children)

  # Level 2: aggregates from the level-1 parents (must run after level 1)
  aggregate_parents <- list(
    "Capacity|Electricity|Fossil" = c("Capacity|Electricity|Coal", "Capacity|Electricity|Gas", "Capacity|Electricity|Oil"),
    "Capacity|Electricity|Non-Biomass Renewables" = c("Capacity|Electricity|Solar", "Capacity|Electricity|Wind",
                                                       "Capacity|Electricity|Hydro", "Capacity|Electricity|Geothermal")
  )
  data <- sum_children_into_parents(data, aggregate_parents)

  cat("Fixed parent capacity variables (Coal, Gas, Oil, Biomass, Solar, Wind, Fossil, Non-Biomass Renewables)\n")

  data
}
