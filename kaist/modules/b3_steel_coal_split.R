################################################################################
# b3: Coal feedstock/fuel split for Iron and Steel (Korea only, query-based)
#
# GCAM doesn't distinguish coal feedstock vs fuel at subsector level.
# Use technology-specific ratios based on steel industry literature:
#   - BF (Blast Furnace): 75% feedstock (coke for reduction), 25% fuel (PCI)
#   - BF with H2: 50% feedstock (H2 partially replaces coke), 50% fuel
#   - BF CCS: 75% feedstock, 25% fuel (same as BF)
#   - EAF: 0% feedstock (coal only for heating)
# Data source: "industry final energy by tech and fuel" query from .prj file
#
# Skips with a message when the query is absent from the .dat.
# (An older standalone version of this split that patched step4 output from
# an MT xlsx lives in kaist/diagnostics/split_coal_fuel_feedstock.R -- this
# module is the canonical one.)
################################################################################

split_steel_coal <- function(data, prj, target_rgn = target_region) {
  year_columns <- names(data)[grepl("^[0-9]{4}$", names(data))]

  cat("\n=== Coal Feedstock/Fuel Split for Iron and Steel (Query-based) ===\n")

  is_energy <- tryCatch({
    getQuery(prj, "industry final energy by tech and fuel") %>%
      filter(grepl("iron", sector, ignore.case = TRUE),
             region == target_rgn,
             grepl("coal", input, ignore.case = TRUE))
  }, error = function(e) {
    cat("Warning: Could not load 'industry final energy by tech and fuel':", e$message, "\n")
    NULL
  })

  if (is.null(is_energy) || nrow(is_energy) == 0) {
    cat("Skipped Iron and Steel coal feedstock split (query not available)\n")
    return(data)
  }

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
    is_coal_idx <- which(data$Variable == is_coal_var & data$Scenario == scen)
    if (length(is_coal_idx) == 0) next

    fuel_row <- data[is_coal_idx[1], ]
    fuel_row$Variable <- "Final Energy|Industry|Iron and Steel|Coal|Fuel"

    feed_row <- data[is_coal_idx[1], ]
    feed_row$Variable <- "Final Energy|Industry|Iron and Steel|Coal|Feedstock"

    for (yr_col in year_columns) {
      yr <- as.numeric(yr_col)
      ratio_row <- coal_ratios %>% filter(scenario == scen, year == yr)
      total_val <- as.numeric(data[is_coal_idx[1], yr_col])
      if (nrow(ratio_row) > 0 && !is.na(total_val)) {
        fuel_row[[yr_col]] <- total_val * ratio_row$fuel_ratio[1]
        feed_row[[yr_col]] <- total_val * ratio_row$feedstock_ratio[1]
      } else {
        fuel_row[[yr_col]] <- total_val  # Default: treat as all fuel
        feed_row[[yr_col]] <- 0
      }
    }

    data <- rbind(data, fuel_row, feed_row)
  }

  cat("Created Iron and Steel Coal Fuel/Feedstock split variables\n")

  data
}
