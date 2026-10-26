################################################################################
# b9: LULUCF inventory adjustment (Korea only)
#
# Runs with a Korean LULUCF path (gcam-kaist9 LULUCF PR #2, NMSF2) carry the gas
# CO2_LULUCF_adj, which brings GCAM land-use CO2 to the inventory coverage and
# counts in the GHG_Kor cap. gcamreport reads only CO2 and CO2_FUG, so the gas
# is missing from the report. This adds it (MtC x 44/12) to the CO2 and Kyoto
# AFOLU rows and totals, and as its own row. Needs the "LULUCF inventory
# adjustment by region" query in the project (kaist/kmip/data/nmsf2_queries.xml, settings project_queries); skips
# otherwise.
################################################################################

add_lulucf_adjustment <- function(data, prj, target_rgn = target_region) {
  year_columns <- year_cols(data)
  cat("\n=== LULUCF inventory adjustment ===\n")

  q <- tryCatch(getQuery(prj, "LULUCF inventory adjustment by region"), error = function(e) NULL)
  if (is.null(q) || nrow(q) == 0) {
    cat("Skipped LULUCF inventory adjustment (query not in project)\n")
    return(data)
  }

  adj <- q %>%
    filter(region == target_rgn, scenario %in% unique(data$Scenario)) %>%
    group_by(scenario, year) %>%
    summarise(value = sum(value) * 44 / 12, .groups = "drop")   # MtC -> Mt CO2

  new_row <- long_to_rows(adj %>% mutate(Variable = "Emissions|CO2|AFOLU|LULUCF Inventory Adjustment"),
                          data, tibble::tibble(Variable = "Emissions|CO2|AFOLU|LULUCF Inventory Adjustment",
                                               Unit = "Mt CO2/yr"))

  # rows that include LULUCF CO2 (Kyoto Gases in CO2-equiv, GWP of CO2 = 1)
  targets <- c("Emissions|CO2|AFOLU", "Emissions|CO2|AFOLU [NGHGI]", "Emissions|CO2",
               "Emissions|Kyoto Gases|AFOLU", "Emissions|Kyoto Gases")
  for (i in which(data$Variable %in% targets)) {
    r <- new_row[new_row$Scenario == data$Scenario[i], ]
    data[i, year_columns] <- data[i, year_columns] + r[1, year_columns]
  }
  cat(sprintf("Added %s to %d rows\n", "CO2_LULUCF_adj", sum(data$Variable %in% targets)))
  bind_rows(data, new_row)
}
