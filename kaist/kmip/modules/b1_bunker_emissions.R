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
# What we do (settings: bunker_mode, default "split"):
#   1. "split": redistribute Aviation/Shipping by Korean domestic ratios (9.9%, 3.9%).
#      GCAM's Domestic Aviation holds most of Korea's international flights, so the
#      pooled aviation and shipping are re-split. "intl": no re-split; the database
#      was built with the L154 split (Domestic Aviation / Domestic Ship calibrated to
#      GIR), so the Bunkers rows (trn_aviation_intl, trn_shipping_intl) are the
#      international emissions as they are.
#   2. Transportation += domestic change (Domestic values changed; 0 in "intl")
#   3. Bunkers += international change (International values changed; 0 in "intl")
#   4. Demand, Energy, Energy and Industrial Processes and the Emissions|{gas}
#      total -= original international (exclude bunkers from all totals)
# Applied to CO2 / N2O / CH4 and to the Kyoto Gases (CO2eq) tree, one
# scenario at a time; a missing leaf row (e.g. CH4 aviation) counts as 0.
# gcamreport's CO2 rows already follow the "(no bio)" sector query, so the Bunkers
# rows carry the biomass credit of their fuel, and the domestic total that step 4
# leaves is the no-bio total minus the two international sectors.
#
# Hardcoded assumptions (domestic ratios 0.099 / 0.039, min_year 2020):
# Source: GIR 2025 national GHG inventory, 2023 (domestic / (domestic + intl)).
# see kaist/docs/hardcoded_assumptions.md (local-only note; gitignored)
################################################################################

# One gas, one scenario at a time so multi-scenario data cannot misalign and
# a leaf missing for one scenario (e.g. no CH4 aviation rows) is treated as 0.
# resplit = FALSE ("intl" mode) keeps the domestic and international rows as they are.
reallocate_bunker_emissions <- function(data, gas, adj_cols,
                                        aviation_dom_ratio = 0.099,
                                        shipping_dom_ratio = 0.039,
                                        resplit = TRUE) {
  n <- length(adj_cols)
  dom_change_all <- 0
  intl_removed_all <- 0
  touched <- FALSE

  for (scen in unique(data$Scenario)) {
    row_of <- function(suffix) {
      which(data$Scenario == scen &
              data$Variable == paste0("Emissions|", gas, suffix))
    }
    vals_of <- function(idx) {
      if (length(idx) == 0) rep(0, n) else as.numeric(unlist(data[idx, adj_cols]))
    }

    dom_avi_i  <- row_of("|Energy|Demand|Transportation|Domestic Aviation")
    intl_avi_i <- row_of("|Energy|Demand|Bunkers|International Aviation")
    dom_shp_i  <- row_of("|Energy|Demand|Transportation|Domestic Shipping")
    intl_shp_i <- row_of("|Energy|Demand|Bunkers|International Shipping")
    if (length(c(dom_avi_i, intl_avi_i, dom_shp_i, intl_shp_i)) == 0) next

    dom_avi  <- vals_of(dom_avi_i)
    intl_avi <- vals_of(intl_avi_i)
    dom_shp  <- vals_of(dom_shp_i)
    intl_shp <- vals_of(intl_shp_i)

    # Redistribute aviation / shipping totals by the Korean domestic ratios ("split" only)
    total_avi <- dom_avi + intl_avi
    total_shp <- dom_shp + intl_shp
    if (resplit) {
      new_dom_avi  <- total_avi * aviation_dom_ratio
      new_intl_avi <- total_avi * (1 - aviation_dom_ratio)
      new_dom_shp  <- total_shp * shipping_dom_ratio
      new_intl_shp <- total_shp * (1 - shipping_dom_ratio)
    } else {
      new_dom_avi <- dom_avi; new_intl_avi <- intl_avi
      new_dom_shp <- dom_shp; new_intl_shp <- intl_shp
    }

    dom_change  <- (new_dom_avi - dom_avi) + (new_dom_shp - dom_shp)
    intl_change <- (new_intl_avi - intl_avi) + (new_intl_shp - intl_shp)
    old_intl_total <- intl_avi + intl_shp

    if (length(dom_avi_i) > 0)  data[dom_avi_i, adj_cols]  <- new_dom_avi
    if (length(intl_avi_i) > 0) data[intl_avi_i, adj_cols] <- new_intl_avi
    if (length(dom_shp_i) > 0)  data[dom_shp_i, adj_cols]  <- new_dom_shp
    if (length(intl_shp_i) > 0) data[intl_shp_i, adj_cols] <- new_intl_shp

    # Update parent variables up to the Emissions|{gas} total ("" suffix).
    # Demand and everything above it exclude the international share.
    total_adj <- dom_change - old_intl_total
    parent_suffixes <- c("|Energy|Demand|Transportation", "|Energy|Demand|Bunkers",
                         "|Energy|Demand", "|Energy",
                         "|Energy and Industrial Processes", "")
    parent_adjs <- list(dom_change, intl_change,
                        total_adj, total_adj, total_adj, total_adj)
    for (i in seq_along(parent_suffixes)) {
      idx <- row_of(parent_suffixes[i])
      if (length(idx) == 0) next
      data[idx, adj_cols] <- as.numeric(unlist(data[idx, adj_cols])) + parent_adjs[[i]]
    }

    dom_change_all <- dom_change_all + sum(dom_change)
    intl_removed_all <- intl_removed_all + sum(old_intl_total)
    touched <- TRUE
  }

  if (touched) {
    cat("Reallocated", gas, ": dom_change =", round(dom_change_all, 2),
        ", removed intl =", round(intl_removed_all, 2), "\n")
  } else {
    cat("Warning: no aviation/shipping rows for", gas, "- skipped\n")
  }
  data
}

# Apply the reallocation to every gas, adjusting only years >= min_year.
# mode: "split" (re-split by the domestic ratios) or "intl" (database built with the
# L154 split: Bunkers rows taken as they are); settings file: bunker_mode.
reallocate_all_bunker_emissions <- function(data,
                                            gases = c("CO2", "N2O", "CH4", "Kyoto Gases"),
                                            min_year = 2020,
                                            mode = get0("bunker_mode", ifnotfound = "split")) {
  if (!mode %in% c("split", "intl")) stop("bunker_mode must be \"split\" or \"intl\", not ", mode)
  cat("\n=== Bunkers (b1), mode", mode, "===\n")
  year_columns <- year_cols(data)
  adj_year_cols <- year_columns[as.numeric(year_columns) >= min_year]

  for (gas in gases) {
    data <- reallocate_bunker_emissions(data, gas, adj_year_cols, resplit = (mode == "split"))
  }
  data
}
