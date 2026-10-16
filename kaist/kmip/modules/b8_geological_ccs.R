################################################################################
# b8: CCS by demand sector, geological storage only (Korea only)
#
# gcamreport puts feedstock carbon (carbon kept in plastics etc.) into
# Carbon Capture|Utilization and into Carbon Capture|Energy|Demand|Industry|*.
# KMIP "Carbon Sequestration|CCS|..." rows mean stored CO2, so this adds
#   Carbon Capture|Geological Storage|Energy|Demand[|Industry|<sector>]
# from the "CO2 sequestration by tech" query, keeping only technologies that
# carbon_seq_tech_map sends to Carbon Capture|Geological Storage.
################################################################################

add_geological_ccs <- function(data, prj, target_rgn = target_region) {
  cat("\n=== Geological CCS by demand sector ===\n")

  q <- tryCatch(getQuery(prj, "CO2 sequestration by tech"), error = function(e) NULL)
  if (is.null(q) || nrow(q) == 0) {
    cat("Skipped geological CCS rows (query not available)\n")
    return(data)
  }

  map <- load_gcam_rda("carbon_seq_tech_map")
  geo <- map %>% filter(var == "Carbon Capture|Geological Storage") %>% distinct(sector, technology)
  demand_vars <- map %>%
    semi_join(geo, by = c("sector", "technology")) %>%
    filter(grepl("^Carbon Capture\\|Energy\\|Demand", var)) %>%
    mutate(unit_conv = as.numeric(unit_conv),
           Variable = sub("^Carbon Capture\\|", "Carbon Capture|Geological Storage|", var))

  # the parent rows are always written, also when no technology is used (0)
  targets <- tibble::tibble(
    Variable = unique(c(paste0("Carbon Capture|Geological Storage|Energy|Demand",
                               c("", "|Industry", "|Industry|Chemicals", "|Industry|Iron and Steel",
                                 "|Industry|Non-Ferrous Metals", "|Industry|Non-Metallic Minerals",
                                 "|Industry|Other Sector")),
                        demand_vars$Variable)),
    Unit = "Mt CO2/yr")

  long <- q %>%
    filter(region == target_rgn, scenario %in% unique(data$Scenario)) %>%
    inner_join(demand_vars, by = c("sector", "technology"), relationship = "many-to-many") %>%
    mutate(value = value * unit_conv)

  new_rows <- long_to_rows(long, data, targets)
  cat(sprintf("Added %d geological CCS rows\n", nrow(new_rows)))
  bind_rows(data, new_rows)
}
