################################################################################
# b4: Convert Energy Service to vehicle capacity, thousand vehicles (Korea only)
#
# Convert transportation Energy Service (billion pkm/tkm) to vehicle counts
# Method: Use MT 2020 reference vehicle counts to derive a fixed conversion ratio
#         Ratio = MT_2020_total_vehicles / GCAM_2020_energy_service_total
#         Then apply this ratio to all years for each sub-category
#
# Note: GCAM "Plug-in Hybrid" corresponds to MT "Hybrid Liquids" -> template "HEV"
#       This renaming is handled in the mapping template (step3), not here.
#
# ref_scenario: scenario whose 2020 values anchor the ratio (used for ALL
# scenarios). NULL (default) falls back to the first scenario in the data.
#
# Hardcoded assumptions (mt_ldv_2020 / mt_mhdv_2020 reference vehicle counts,
# which must be refreshed when MT publishes new data):
# see kaist/docs/hardcoded_assumptions.md (local-only note; gitignored)
################################################################################

add_vehicle_capacity <- function(data, ref_scenario = NULL) {
  year_columns <- year_cols(data)

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
  if (!is.null(ref_scenario)) {
    ref_scen <- ref_scenario
  } else {
    ref_scen <- unique(data$Scenario)[1]
    cat(sprintf("  No ref_scenario in config.R, using first scenario: %s\n", ref_scen))
  }

  ldv_ref_idx <- which(data$Variable == ldv_vars[1] & data$Scenario == ref_scen)
  mhdv_ref_idx <- which(data$Variable == mhdv_vars[1] & data$Scenario == ref_scen)

  ldv_ratio <- mt_ldv_total / as.numeric(data[ldv_ref_idx[1], "2020"])
  mhdv_ratio <- mt_mhdv_total / as.numeric(data[mhdv_ref_idx[1], "2020"])

  cat(sprintf("  LDV ratio (from %s): %.4f (thousand vehicles / billion pkm)\n", ref_scen, ldv_ratio))
  cat(sprintf("  MHDV ratio (from %s): %.4f (thousand vehicles / billion tkm)\n", ref_scen, mhdv_ratio))

  # Apply ratios to all scenarios
  for (var in ldv_vars) {
    var_idx <- which(data$Variable == var)
    if (length(var_idx) > 0) {
      data[var_idx, year_columns] <- data[var_idx, year_columns] * ldv_ratio
      data[var_idx, "Unit"] <- "thousand vehicles"
    }
  }

  for (var in mhdv_vars) {
    var_idx <- which(data$Variable == var)
    if (length(var_idx) > 0) {
      data[var_idx, year_columns] <- data[var_idx, year_columns] * mhdv_ratio
      data[var_idx, "Unit"] <- "thousand vehicles"
    }
  }

  data
}
