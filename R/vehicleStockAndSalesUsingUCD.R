#
# library(Rcpp)
# library(magrittr)
# library(devtools)
# library(dplyr)
# library(tidyr)
# library(rgcam)
# library(readr)
# # library(gcammaptools)
# library(ggplot2)
# library(gtable)
# library(grid)
# # We also need to make sure that the fonts we want to use are properly loaded into R
# library(extrafont)
# library(RColorBrewer)
# library(gridExtra)
# library(stringr)
# library(tibble)
# library(readxl)
# library(writexl)
#
# # Create a simple function to format all maps into a long table
# gather_map <- function(df){
#   untouched_cols <- names(df) %>% .[!grepl("var", names(df))]
#   df %>%
#     pivot_longer(cols = -all_of(untouched_cols), names_to = "identifier", values_to = "var") %>%
#     select(-identifier) %>%
#     filter(!is.na(var), var != "") %>%
#     return()
# }
#
# long_columns <- c("scenario", "region", "var", "year", "value")
#
#
#
#
# # Energy Service ----------------------------------------------------------
# ## Transportation ------------------
#
# trans_serv <- getQuery(prj, "transport service output by tech and vintage") |>
#   separate(technology, into = c("technology", "vintage"), sep = ",") |>
#   mutate(vintage = as.integer(sub("year=", "", vintage))) |>
#   filter(vintage <= year) |>    ##Only vintages from the model year or before will be in existence
#   rename("mode" = "subsector")
#
#
#
# #### Vehicle stock ----------------------------------
#
# gcam_regions <- unique(trans_serv$region)
#
# # Use the UCD dataset which has load factors and vehicle miles traveled values
# ucd_core_values <- ucd_core |>
#   pivot_longer(names_to = "year", values_to = "value", cols = starts_with("2")) |>
#   mutate(year=as.integer(year)) |>
#   left_join(ucd_size_class) |>
#   # Both types of rail simply called 'Rail' causing errors later
#   mutate(rev.mode = ifelse(rev.mode == "Rail",
#                            ifelse(UCD_sector == "Passenger",
#                                   "Passenger Rail", ifelse(UCD_sector == "Freight",
#                                                            "Freight Rail", rev.mode)), rev.mode)) |>
#   select(-UCD_fuel, -UCD_sector, -mode, -size.class)
#
# ucd_techs <- unique(ucd_core_values$UCD_technology)
# ucd_techs <- ucd_techs[!(ucd_techs == "All")]
#
# # Annual vehicle, is the same across all fuels of cars, so explicity show that:
# ucd_core_loads <- ucd_core_values |>
#   filter(variable == "annual travel per vehicle") |>
#   mutate(UCD_technology = ifelse(UCD_technology == "All", ucd_techs[1], UCD_technology)) |>
#   complete(nesting(UCD_region, rev_size.class, rev.mode, variable, unit, year, value), UCD_technology = ucd_techs) |>
#   bind_rows(ucd_core_values |>
#               filter(variable == "load factor"))
#
#
# # For regions in the UCD dataset that are GCAM regions, keep their values,
# # and for regions that aren't represented in there, use the mean of the other regions
#
# ucd_core_A <- ucd_core_loads |>
#   filter(UCD_region %in% gcam_regions) |>
#   group_by(UCD_region, rev_size.class, rev.mode, variable, UCD_technology, unit, year) |>
#   summarise(value=mean(value, na.rm = T)) |>
#   ungroup()
#
# ucd_core_B <- ucd_core_loads |>
#   filter(!(UCD_region %in% gcam_regions)) |>
#   ##filter(rev_size.class %in% c("Car", "Light truck")) |>
#   group_by(rev_size.class, rev.mode, variable, UCD_technology, unit, year) |>
#   summarise(value=mean(value, na.rm = T)) |>
#   ungroup() |>
#   mutate(UCD_region = "South America_Northern") |>
#   complete(nesting(rev_size.class, rev.mode, variable, UCD_technology, unit, year, value), UCD_region = gcam_regions[!(gcam_regions %in% unique(ucd_core_A$UCD_region))])
#
# ## View the following to see that annual travel per vehicle is in vkt/(vehicle*yr)
# ## and load factors are in pass/vehicle and tonnes/vehicle
# # unique(ucd_core_loads |>
# #          select(-UCD_region, -year, -value, -UCD_technology))
#
# ucd_core_gcamRegions <- bind_rows(ucd_core_A, ucd_core_B) |>
#   select(-unit) |>
#   pivot_wider(names_from = "variable", values_from = "value")
#
# trans_stock_clean <- trans_serv |>
#   left_join(ucd_core_gcamRegions, by = c("region"="UCD_region","mode"="rev_size.class", "year", "technology"="UCD_technology")) |>
#   filter(!(is.na(`annual travel per vehicle`)),
#          !(is.na(`load factor`))) |>
#   mutate(value=(value / `load factor` / `annual travel per vehicle`),
#          Units = "million vehicles") |>
#   left_join(transport_stock_map, by = c("sector", "mode", "technology"), relationship = "many-to-many") |>
#   filter(!is.na(var)) |>
#   mutate(value = value * unit_conv) |>
#   group_by(scenario, region, year, var, Units) |>
#   summarise(value = sum(value, na.rm = T)) |>
#   ungroup() |>
#   select(all_of(long_columns), Units)
#
#
# ### Vehicle sales -------------------------
#
# vintaged_modes = trans_serv |>
#   filter(year != vintage,
#          value != 0) |>
#   select(sector, mode, Units) |>
#   unique()
#
# trans_serv_new <- trans_serv %>%
#   filter(year == vintage)    ## only look at new sales in each year
#
# trans_sales_clean <- trans_serv_new |>
#   left_join(ucd_core_gcamRegions, by = c("region"="UCD_region","mode"="rev_size.class", "year", "technology"="UCD_technology")) |>
#   filter(!(is.na(`annual travel per vehicle`)),
#          !(is.na(`load factor`)),
#          mode %in% unique(vintaged_modes$mode)) |>
#   # Assume constant sales during the 5 year period
#   mutate(value=(value / `load factor` / `annual travel per vehicle` / 5),
#          Units = "million vehicles") |>
#   left_join(transport_sales_map, by = c("sector", "mode", "technology"), relationship = "many-to-many") |>
#   filter(!is.na(var)) |>
#   mutate(value = value * unit_conv) |>
#   group_by(scenario, region, year, var, Units) |>
#   summarise(value = sum(value, na.rm = T)) |>
#   ungroup() |>
#   select(all_of(long_columns), Units)
#
# rm(ucd_core_A, ucd_core_B)
#
