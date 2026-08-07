################################################################################
# b1: Reallocate aviation and shipping emissions (Korea only)
#
# Variable hierarchy (gcamreport structure):
#   Emissions|{gas}|Energy
#   |-- Demand                         <- includes Bunkers (international)
#   |   |-- Transportation             <- Domestic only (Aviation, Shipping, Bus, Rail...)
#   |   |   |-- Domestic Aviation
#   |   |   |-- Domestic Shipping
#   |   |-- Bunkers                    <- International only
#   |   |   |-- International Aviation
#   |   |   |-- International Shipping
#   |   |-- Industry, Residential...
#   |-- Supply
#
# What we do:
#   1. Redistribute Aviation/Shipping by Korean domestic ratios (9.3%, 3.2%)
#   2. Transportation += domestic change (Domestic values changed)
#   3. Bunkers += international change (International values changed)
#   4. Demand, Energy -= original international (exclude bunkers from totals)
################################################################################

reallocate_bunker_emissions <- function(data, gas, adj_cols,
                                        aviation_dom_ratio = 0.093,
                                        shipping_dom_ratio = 0.032) {
  # Helper to get row index and values
  get_vals <- function(var) {
    idx <- which(data$Variable == paste0("Emissions|", gas, "|Energy|Demand|", var))
    if (length(idx) == 0) return(list(idx = NULL, vals = NULL))
    list(idx = idx, vals = as.numeric(unlist(data[idx, adj_cols])))
  }

  # Get all required variables
  dom_avi <- get_vals("Transportation|Domestic Aviation")
  intl_avi <- get_vals("Bunkers|International Aviation")
  dom_shp <- get_vals("Transportation|Domestic Shipping")
  intl_shp <- get_vals("Bunkers|International Shipping")

  if (is.null(dom_avi$idx) || is.null(intl_avi$idx) ||
      is.null(dom_shp$idx) || is.null(intl_shp$idx)) {
    cat("Warning: Missing variables for", gas, "\n")
    return(data)
  }

  # Redistribute
  total_avi <- dom_avi$vals + intl_avi$vals
  total_shp <- dom_shp$vals + intl_shp$vals

  new_dom_avi <- total_avi * aviation_dom_ratio
  new_intl_avi <- total_avi * (1 - aviation_dom_ratio)
  new_dom_shp <- total_shp * shipping_dom_ratio
  new_intl_shp <- total_shp * (1 - shipping_dom_ratio)

  # Changes
  dom_change <- (new_dom_avi - dom_avi$vals) + (new_dom_shp - dom_shp$vals)
  intl_change <- (new_intl_avi - intl_avi$vals) + (new_intl_shp - intl_shp$vals)
  old_intl_total <- intl_avi$vals + intl_shp$vals

  # Update values
  data[dom_avi$idx, adj_cols] <- new_dom_avi
  data[intl_avi$idx, adj_cols] <- new_intl_avi
  data[dom_shp$idx, adj_cols] <- new_dom_shp
  data[intl_shp$idx, adj_cols] <- new_intl_shp

  # Update parent variables
  for (var in c("Transportation", "Bunkers", "Demand", "")) {
    full_var <- paste0("Emissions|", gas, "|Energy|Demand")
    if (var != "") full_var <- paste0(full_var, "|", var)
    if (var == "") full_var <- paste0("Emissions|", gas, "|Energy")

    idx <- which(data$Variable == full_var)
    if (length(idx) == 0) next

    adj <- switch(var,
      "Transportation" = dom_change,
      "Bunkers" = intl_change,
      dom_change - old_intl_total  # Demand and Energy: exclude international
    )
    data[idx, adj_cols] <- as.numeric(unlist(data[idx, adj_cols])) + adj
  }

  cat("Reallocated", gas, ": dom_change =", round(sum(dom_change), 2),
      ", removed intl =", round(sum(old_intl_total), 2), "\n")
  data
}

# Apply the reallocation to every gas, adjusting only years >= min_year.
reallocate_all_bunker_emissions <- function(data, gases = c("CO2", "N2O", "CH4"),
                                            min_year = 2020) {
  year_columns <- names(data)[grepl("^[0-9]{4}$", names(data))]
  adj_year_cols <- year_columns[as.numeric(year_columns) >= min_year]

  for (gas in gases) {
    data <- reallocate_bunker_emissions(data, gas, adj_year_cols)
  }
  data
}
