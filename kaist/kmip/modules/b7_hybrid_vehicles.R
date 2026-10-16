################################################################################
# b7: Hybrid vehicle Energy Service rows (Korea only)
#
# gcamreport maps the GCAM "Hybrid Liquids" technology into Internal Combustion,
# so the KMIP HEV rows had no source. This adds
#   Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Hybrid
#   Energy Service|Transportation|Freight|Truck|Hybrid
# from the "transport service output by tech and vintage" query (billion
# pkm/tkm, same basis as gcamreport). Internal Combustion is left as it is; the
# mapping subtracts the Hybrid row for ICEV. Must run before b4.
################################################################################

add_hybrid_vehicles <- function(data, prj, target_rgn = target_region) {
  year_columns <- year_cols(data)
  cat("\n=== Hybrid vehicle Energy Service rows ===\n")

  q <- tryCatch(getQuery(prj, "transport service output by tech and vintage"),
                error = function(e) NULL)
  if (is.null(q) || nrow(q) == 0) {
    cat("Skipped hybrid rows (query not available)\n")
    return(data)
  }

  targets <- tibble::tribble(
    ~sector,                ~Variable,                                                                 ~Unit,
    "trn_pass_road_LDV_4W", "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Hybrid", "billion pkm/yr",
    "trn_freight_road",     "Energy Service|Transportation|Freight|Truck|Hybrid",                     "billion tkm/yr"
  )

  hyb <- q %>%
    filter(region == target_rgn, scenario %in% unique(data$Scenario),
           sector %in% targets$sector,
           sub(",year=.*", "", technology) == "Hybrid Liquids") %>%
    # gcamreport reports billion pkm/tkm
    mutate(value = ifelse(grepl("^million ", Units), value / 1000, value)) %>%
    group_by(scenario, sector, year) %>%
    summarise(value = sum(value), .groups = "drop") %>%
    inner_join(targets, by = "sector")

  new_rows <- long_to_rows(hyb, data, targets)
  cat(sprintf("Added %d hybrid rows\n", nrow(new_rows)))
  bind_rows(data, new_rows)
}

# Build report rows (one per scenario x target Variable, all years, missing = 0)
# from a long table with scenario, year, Variable, value. Shared with b8.
long_to_rows <- function(long, data, targets) {
  year_columns <- year_cols(data)
  scens <- unique(data$Scenario)
  base <- tidyr::expand_grid(Scenario = scens, distinct(targets, Variable, Unit))
  wide <- long %>%
    filter(as.character(year) %in% year_columns) %>%
    group_by(Scenario = scenario, Variable, year = as.character(year)) %>%
    summarise(value = sum(value), .groups = "drop") %>%
    tidyr::pivot_wider(names_from = year, values_from = value)
  out <- base %>%
    left_join(wide, by = c("Scenario", "Variable")) %>%
    mutate(Model = unique(data$Model)[1], Region = unique(data$Region)[1])
  for (y in setdiff(year_columns, names(out))) out[[y]] <- NA_real_
  out %>%
    mutate(across(all_of(year_columns), ~ tidyr::replace_na(as.numeric(.), 0))) %>%
    select(all_of(names(data)))
}
