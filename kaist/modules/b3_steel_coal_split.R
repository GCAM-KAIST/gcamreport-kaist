################################################################################
# b3: Iron and Steel coal -> Coal|Fuel + Coal|Feedstock (Korea only)
#
#   Coal|Feedstock = sector coal x BF-family share (by year) x 0.5832
#   Coal|Fuel      = the rest
# 0.5832 = MT 2020 Coal|Feedstock / Coal total (read from mt_reference_path).
# BF family = BLASTFUR* techs. EAF-DRI coal is all Fuel.
# Method: kaist/steel/README.md section 3. Skips if the query is missing.
################################################################################

split_steel_coal <- function(data, prj, target_rgn = target_region) {
  year_columns <- year_cols(data)

  cat("\n=== Coal Fuel/Feedstock Split for Iron and Steel (MT 2020 ratio) ===\n")

  is_coal <- tryCatch({
    getQuery(prj, "industry final energy by tech and fuel") %>%
      filter(grepl("iron", sector, ignore.case = TRUE),
             region == target_rgn,
             grepl("coal", input, ignore.case = TRUE))
  }, error = function(e) {
    cat("Warning: Could not load 'industry final energy by tech and fuel':", e$message, "\n")
    NULL
  })

  if (is.null(is_coal) || nrow(is_coal) == 0) {
    cat("Skipped Iron and Steel coal feedstock split (query not available)\n")
    return(data)
  }

  ref <- mt_steel_reference_2020()
  fs_share <- ref$coal_feedstock / (ref$coal_fuel + ref$coal_feedstock)
  cat(sprintf("MT 2020 feedstock share = %.4f (source: %s)\n", fs_share, ref$source))

  bf_pattern <- "^BLASTFUR"
  techs <- unique(is_coal$technology)
  cat("Coal-using technologies:", paste(techs, collapse = ", "), "\n")
  cat("BF family:", paste(grep(bf_pattern, techs, value = TRUE), collapse = ", "), "\n")

  # BF-family share of sector coal, per scenario and year
  coal_ratios <- is_coal %>%
    group_by(scenario, year) %>%
    summarise(
      total_coal = sum(value, na.rm = TRUE),
      bf_coal    = sum(value[grepl(bf_pattern, technology)], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      bf_share        = ifelse(total_coal > 0, bf_coal / total_coal, 0),
      feedstock_ratio = bf_share * fs_share,
      fuel_ratio      = 1 - feedstock_ratio
    )

  if (debug_on()) {
    cat("BF-family share and Feedstock/Fuel ratios by scenario and year:\n")
    print(coal_ratios %>%
      filter(year %in% seq(2020, 2050, 5)) %>%
      select(scenario, year, bf_share, feedstock_ratio, fuel_ratio))
  }

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
