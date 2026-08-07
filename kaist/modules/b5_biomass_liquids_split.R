################################################################################
# b5: Biomass origin split for Final Energy Liquids (Korea only)
#     -- national blend-share allocation
#
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
################################################################################

split_biomass_liquids <- function(data) {
  year_columns <- names(data)[grepl("^[0-9]{4}$", names(data))]

  cat("\n=== Biomass Origin Split for Final Energy Liquids (National Blend-Share) ===\n")

  # se = Secondary Energy (supply side, where GCAM still tracks biomass origin)
  se_liquids_total <- data %>% filter(Variable == "Secondary Energy|Liquids")
  se_liquids_bio   <- data %>% filter(Variable == "Secondary Energy|Liquids|Biomass")

  if (nrow(se_liquids_total) == 0 || nrow(se_liquids_bio) == 0) {
    cat("Skipped Biomass|Liquids allocation -- Secondary Energy|Liquids(|Biomass)",
        "not present in this run's queried variables\n")
    return(data)
  }

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

    for (scen in unique(data$Scenario)) {
      src_row <- data %>% filter(Variable == src_var, Scenario == scen)
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
  for (scen in unique(data$Scenario)) {
    dac_row <- data %>% filter(Variable == "Final Energy|Industry|Liquids", Scenario == scen)
    if (nrow(dac_row) == 0) next
    new_row <- dac_row[1, ]
    new_row$Variable <- "Final Energy|Direct Air Capture|Biomass|Liquids"
    new_row[, year_columns] <- 0
    biomass_liquids_rows[[length(biomass_liquids_rows) + 1]] <- new_row
  }

  if (length(biomass_liquids_rows) > 0) {
    data <- rbind(data, bind_rows(biomass_liquids_rows))
    cat("Created", length(biomass_liquids_rows),
        "Final Energy|...|Biomass|Liquids rows via national blend-share allocation\n")
  }

  data
}
