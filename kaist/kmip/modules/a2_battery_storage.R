################################################################################
# a2: Battery storage capacity (all regions)
#
# Builds Capacity|Electricity|...|Battery Storage rows from PV_storage /
# wind_storage generation and regional capacity factors, replacing any
# existing Battery Storage rows.
#
# Inputs:
#   elec_gen - result of getQuery(prj, "elec gen by gen tech")
#   cf_rgn   - regional capacity factor table (data/cf_rgn_v*.rda, already
#              patched by patch_gcam_data(): South Korea renewable CF
#              overrides + Korea conventional CFs)
################################################################################

add_battery_storage <- function(data, elec_gen, cf_rgn) {
  storage_gen <- elec_gen %>%
    filter(technology %in% c("PV_storage", "wind_storage"))

  cf_storage <- cf_rgn %>%
    filter(stub.technology %in% c("PV_storage", "wind_storage")) %>%
    select(region, technology = stub.technology, year, cf = capacity.factor)

  battery_storage <- storage_gen %>%
    left_join(cf_storage, by = c("region", "technology", "year")) %>%
    mutate(battery_capacity_gw = (value / (cf * 8760)) * 1e9 / 3600) %>%
    select(scenario, region, subsector, technology, year, battery_capacity_gw) %>%
    pivot_wider(names_from = year, values_from = battery_capacity_gw) %>%
    mutate(
      Model = model_name,
      Region = region,
      Variable = case_when(
        technology == "PV_storage" ~ "Capacity|Electricity|Solar|PV|Battery Storage",
        technology == "wind_storage" ~ "Capacity|Electricity|Wind|Battery Storage"
      ),
      Unit = "GW"
    ) %>%
    rename(Scenario = scenario) %>%
    select(Model, Scenario, Region, Variable, Unit, everything(), -region, -subsector, -technology)

  data %>%
    filter(!grepl("Battery Storage", Variable)) %>%
    bind_rows(battery_storage)
}
