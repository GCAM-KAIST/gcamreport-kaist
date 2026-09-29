################################################################################
# b5: Biomass origin split for Final Energy Liquids (Korea only)
#
# GCAM blends all liquid fuels into one national refining pool, so gcamreport
# has no Final Energy|...|Biomass|Liquids variables. Because the pool is
# homogeneous, the national share is exact for every sector:
#   bio_share        = Secondary Energy|Liquids|Biomass / Secondary Energy|Liquids
#   Biomass|Liquids  = Liquids * bio_share          (new rows)
#   Liquids          = Liquids * (1 - bio_share)    (scaled in place)
# The biomass part is MOVED, not duplicated (double-counting fix, 2026-08-24;
# same logic as build_steel_template.py section 2b). Sector sources match the
# mapping's "...|Oil" rows, so every sector total stays unchanged.
# The mapping's parent "...|Biomass" rows add these Biomass|Liquids variables
# (parent = Solids + Liquids). Details: kaist/docs/hardcoded_assumptions.md.
################################################################################

split_biomass_liquids <- function(data) {
  year_columns <- year_cols(data)

  cat("\n=== Biomass Origin Split for Final Energy Liquids (National Blend-Share) ===\n")

  se_liquids_total <- data %>% filter(Variable == "Secondary Energy|Liquids")
  se_liquids_bio   <- data %>% filter(Variable == "Secondary Energy|Liquids|Biomass")

  if (nrow(se_liquids_total) == 0 || nrow(se_liquids_bio) == 0) {
    cat("Skipped Biomass|Liquids allocation -- Secondary Energy|Liquids(|Biomass)",
        "not present in this run's queried variables\n")
    return(data)
  }

  # bio_share per (scenario, year)
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

  if (debug_on()) {
    cat("biomass_share = Secondary Energy|Liquids|Biomass / Secondary Energy|Liquids:\n")
    print(biomass_share %>%
      filter(year %in% as.character(seq(2020, 2050, 5))) %>%
      select(Scenario, year, biomass_share))
  }

  # KMIP target <- GCAM source Liquids variables (";"-separated), same scope
  # as the mapping's matching "...|Oil" row. Top-level Biomass|Liquids feeds
  # the "Final Energy|Biomass" parent row. "biomass" lowercase = template typo.
  biomass_liquids_targets <- tribble(
    ~template_variable,                                           ~source_variables,
    "Final Energy|Biomass|Liquids",                                "Final Energy|Liquids",
    "Final Energy|Industry|Biomass|Liquids",                       "Final Energy|Industry|Liquids; Final Energy|Non-Energy Use|Liquids",
    "Final Energy|Industry|Chemicals|Biomass|Liquids",             "Final Energy|Industry|Chemicals|Liquids",
    "Final Energy|Industry|Iron and Steel|Biomass|Liquids",        "Final Energy|Industry|Iron and Steel|Liquids",
    "Final Energy|Industry|Non-Metallic Minerals|Biomass|Liquids", "Final Energy|Industry|Non-Metallic Minerals|Cement|Liquids",
    "Final Energy|Industry|Other Sector|biomass|Liquids",          "Final Energy|Industry|Other Sector|Liquids",
    "Final Energy|Transportation|Biomass|Liquids",                 "Final Energy|Transportation|Liquids",
    "Final Energy|Transportation|Road|Biomass|Liquids",            "Final Energy|Transportation|Bus|Liquids; Final Energy|Transportation|Light-Duty Vehicle|Liquids; Final Energy|Transportation|Truck|Liquids",
    "Final Energy|Transportation|Rail|Biomass|Liquids",            "Final Energy|Transportation|Rail|Liquids",
    "Final Energy|Transportation|Ship|Biomass|Liquids",            "Final Energy|Transportation|Domestic Shipping|Liquids",
    "Final Energy|Transportation|Air|Biomass|Liquids",             "Final Energy|Transportation|Domestic Aviation|Liquids",
    "Final Energy|Building|Biomass|Liquids",                       "Final Energy|Residential and Commercial|Liquids",
    "Final Energy|Building|Residential|Biomass|Liquids",           "Final Energy|Residential|Liquids",
    "Final Energy|Building|Commercial/Public|Biomass|Liquids",     "Final Energy|Commercial|Liquids",
    "Final Energy|AFOFI|Biomass|Liquids",                          "Final Energy|Agriculture|Liquids"
  )

  # Build Biomass|Liquids rows from the ORIGINAL (pre-scaling) Liquids values
  biomass_liquids_rows <- list()
  original_liquids_sums <- list()   # for the consistency check below

  for (i in seq_len(nrow(biomass_liquids_targets))) {
    tgt_var  <- biomass_liquids_targets$template_variable[i]
    src_vars <- trimws(strsplit(biomass_liquids_targets$source_variables[i], ";")[[1]])

    for (scen in unique(data$Scenario)) {
      scen_share <- biomass_share %>% filter(Scenario == scen)
      if (nrow(scen_share) == 0) next
      share <- setNames(scen_share$biomass_share, scen_share$year)

      src_sum <- setNames(rep(0, length(year_columns)), year_columns)
      meta_row <- NULL
      for (src_var in src_vars) {
        src_row <- data %>% filter(Variable == src_var, Scenario == scen)
        if (nrow(src_row) == 0) next
        if (is.null(meta_row)) meta_row <- src_row[1, ]
        vals <- as.numeric(src_row[1, year_columns])
        vals[is.na(vals)] <- 0
        src_sum <- src_sum + vals
      }
      if (is.null(meta_row)) next

      new_row <- meta_row
      new_row$Variable <- tgt_var
      new_row[, year_columns] <- as.list(src_sum * share[year_columns])
      biomass_liquids_rows[[length(biomass_liquids_rows) + 1]] <- new_row
      original_liquids_sums[[paste(tgt_var, scen, sep = "||")]] <- src_sum
    }
  }

  # DAC: GCAM has no DAC liquids variable at all -> hard 0
  for (scen in unique(data$Scenario)) {
    dac_row <- data %>% filter(Variable == "Final Energy|Industry|Liquids", Scenario == scen)
    if (nrow(dac_row) == 0) next
    new_row <- dac_row[1, ]
    new_row$Variable <- "Final Energy|Direct Air Capture|Biomass|Liquids"
    new_row[, year_columns] <- 0
    biomass_liquids_rows[[length(biomass_liquids_rows) + 1]] <- new_row
  }

  # Scale every Final Energy|...|Liquids row by (1 - bio_share)
  liquids_mask <- grepl("^Final Energy\\|", data$Variable) &
    grepl("\\|Liquids$", data$Variable) &
    !grepl("\\|[Bb]iomass\\|Liquids$", data$Variable)

  n_scaled <- 0
  for (scen in unique(data$Scenario)) {
    scen_share <- biomass_share %>% filter(Scenario == scen)
    if (nrow(scen_share) == 0) next
    share <- setNames(scen_share$biomass_share, scen_share$year)

    idx <- which(liquids_mask & data$Scenario == scen)
    if (length(idx) == 0) next
    for (yr in year_columns) {
      data[idx, yr] <- data[idx, yr] * (1 - share[[yr]])
    }
    n_scaled <- n_scaled + length(idx)
  }
  cat("Scaled", n_scaled, "Final Energy|...|Liquids rows by (1 - biomass_share)\n")

  if (length(biomass_liquids_rows) > 0) {
    data <- rbind(data, bind_rows(biomass_liquids_rows))
    cat("Created", length(biomass_liquids_rows),
        "Final Energy|...|Biomass|Liquids rows via national blend-share allocation\n")
  }

  # Consistency check: Liquids_new + Biomass|Liquids == Liquids_old per sector
  max_resid <- 0
  n_checked <- 0
  for (key in names(original_liquids_sums)) {
    parts   <- strsplit(key, "||", fixed = TRUE)[[1]]
    tgt_var <- parts[1]
    scen    <- parts[2]
    src_vars <- trimws(strsplit(
      biomass_liquids_targets$source_variables[
        biomass_liquids_targets$template_variable == tgt_var], ";")[[1]])

    new_sum <- setNames(rep(0, length(year_columns)), year_columns)
    for (src_var in src_vars) {
      src_row <- data %>% filter(Variable == src_var, Scenario == scen)
      if (nrow(src_row) == 0) next
      vals <- as.numeric(src_row[1, year_columns])
      vals[is.na(vals)] <- 0
      new_sum <- new_sum + vals
    }
    bio_row  <- data %>% filter(Variable == tgt_var, Scenario == scen)
    bio_vals <- as.numeric(bio_row[1, year_columns])
    bio_vals[is.na(bio_vals)] <- 0

    resid <- max(abs(new_sum + bio_vals - original_liquids_sums[[key]]))
    if (resid >= 1e-9) {
      stop("b5 consistency check FAILED for ", tgt_var, " / ", scen,
           ": max |Liquids_new + Biomass|Liquids - Liquids_old| = ",
           format(resid, digits = 3))
    }
    max_resid <- max(max_resid, resid)
    n_checked <- n_checked + 1
  }
  cat(sprintf(
    "[b5 check] %d sector x scenario pairs OK: max |Liquids_new + Biomass|Liquids - Liquids_old| = %.2e (tolerance 1e-9)\n",
    n_checked, max_resid))

  data
}
