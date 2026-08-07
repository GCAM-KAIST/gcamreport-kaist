################################################################################
# a4: Recalculate Capacity|Electricity using vintage-based calculation
#
# gcamreport bug: cf_iea (from IEA world average) is used instead of cf_gcam/cf_rgn
#   - Renewables: cf_iea duplicates cf_rgn entries, causing averaging
#   - Fossil fuels: cf_iea (~50-60%) used instead of cf_gcam (80-85%)
# (Candidate for an upstream gcamreport issue/PR.)
#
# Fix: Recalculate Capacity using vintage-based generation data and correct CF values
#   - cf_rgn: Regional CF for renewables (wind, PV, CSP)
#   - cf_gcam: Default CF for nuclear (0.9), fossil fuels (0.8-0.85), etc.
#
# Method: For each vintage, Capacity = Generation / (CF * 8760 * conversion)
#         Then sum capacities across all vintages
#
# Inputs:
#   prj     - rgcam project (needs "elec gen by gen tech and cooling tech and
#             vintage"; skips with a message when the query is absent)
#   cf_rgn  - regional CF table (data/cf_rgn_v*.rda, patched by patch_gcam_data)
#   cf_gcam - global default CF table (data/cf_gcam_v*.rda)
#
# Hardcoded assumptions (tech_to_cap table, storage exclusion):
# see kaist/docs/hardcoded_assumptions.md (local-only note; gitignored)
################################################################################

recalc_vintage_capacity <- function(data, prj, cf_rgn, cf_gcam) {
  # Get vintage generation data from GCAM
  elec_gen_vintage <- tryCatch({
    getQuery(prj, "elec gen by gen tech and cooling tech and vintage")
  }, error = function(e) {
    cat("Warning: Could not load vintage query:", e$message, "\n")
    NULL
  })

  if (is.null(elec_gen_vintage) || nrow(elec_gen_vintage) == 0) {
    cat("Skipped capacity recalculation (vintage query not available)\n")
    return(data)
  }

  cat("Loaded vintage generation data:", nrow(elec_gen_vintage), "rows\n")

  # Conversion constants
  EJ_to_GWh <- 3.6e-6
  hr_per_yr <- 8760

  # Technology to capacity variable mapping
  # Includes renewables, nuclear, and fossil fuels
  #
  # NOTE: *_storage techs (wind_storage, PV_storage, CSP_storage) are
  # deliberately commented out to avoid double counting: their capacity is
  # already reported as separate Battery Storage variables by module a2
  # (add_battery_storage). Mapping them here as well would add the same
  # capacity into Onshore/PV/CSP a second time, and a5 would then roll the
  # duplicate into the parent totals.
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
  cf_rgn_lookup <- cf_rgn %>%
    select(region, technology = stub.technology, cf_year = year, cf = capacity.factor)

  cf_gcam_lookup <- cf_gcam %>%
    select(technology, cf_default = `2100`)

  # NOTE: Korea-specific CF overrides for conventional techs (coal, gas, oil,
  # hydro, nuclear, biomass, CSP) are NOT hard-coded here. They are applied at
  # runtime by kaist/functions.R::patch_gcam_data() (kaist_overrides), which
  # adds South Korea rows to cf_rgn, so they are picked up automatically by
  # cf_rgn_lookup above. To change a Korea CF value, edit kaist_overrides in
  # kaist/functions.R.

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
  data_year_cols <- year_cols(data)

  for (cap_var in unique(capacity_total$cap_var)) {
    cap_new <- capacity_total %>% filter(cap_var == !!cap_var)

    for (j in 1:nrow(cap_new)) {
      scen <- cap_new$scenario[j]
      rgn <- cap_new$region[j]
      yr <- as.character(cap_new$year[j])
      new_val <- cap_new$capacity_gw[j]

      if (!yr %in% data_year_cols) next

      # Find matching row in data
      idx <- which(data$Variable == cap_var & data$Scenario == scen & data$Region == rgn)

      if (length(idx) > 0 && !is.na(new_val) && new_val > 0) {
        data[idx[1], yr] <- new_val
      }
    }
  }

  cat("Recalculated Capacity|Electricity using vintage-based calculation with correct CF\n")

  # Debug output (set verbose_debug <- TRUE in kaist/config.R to see it):
  # CF table and generation back-calculation check for the first scenario
  if (debug_on()) {
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
  }

  data
}
