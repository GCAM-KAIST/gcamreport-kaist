################################################################################
# a1: Update CO2 prices -> Price|Carbon rows (all regions)
#
# Replaces the Price|Carbon rows in the report with values taken directly
# from the "CO2 prices" query in the rgcam project (.dat) file.
# Skips (returns data unchanged) if the .dat does not have the query, e.g.
# when step1 was run with desired_variables restricted to Capacity/Emissions.
################################################################################

add_carbon_price <- function(data, prj) {
  co2_prices <- tryCatch(getQuery(prj, "CO2 prices"), error = function(e) NULL)

  if (is.null(co2_prices)) {
    message("Skipping CO2 Prices update -- query not present in .dat.")
    return(data)
  }

  regions_list <- unique(getQuery(prj, "CO2 emissions by region")$region)
  valid_markets <- paste0(regions_list, "CO2")

  co2_price_all <- co2_prices %>%
    filter(market %in% valid_markets) %>%
    select(scenario, market, year, value) %>%
    pivot_wider(names_from = year, values_from = value) %>%
    mutate(
      Model = model_name,
      Region = sub("CO2$", "", market),
      Variable = "Price|Carbon",
      Unit = "1990$/tC"
    ) %>%
    rename(Scenario = scenario) %>%
    select(Model, Scenario, Region, Variable, Unit, everything(), -market)

  data %>%
    filter(Variable != "Price|Carbon") %>%
    bind_rows(co2_price_all)
}
