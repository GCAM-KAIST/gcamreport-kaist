################################################################################
# b6: Iron and Steel process emissions (Korea only)
#
#   process = Coal|Feedstock (ktoe) x 0.00193 Mt CO2/ktoe (MT 2020 ratio)
#   Emissions|CO2|Energy|Demand|Industry|Iron and Steel -= process
#   new row: Emissions|GHGs|Non-Energy|Industrial Process|Iron and Steel
# energy + process = original steel CO2. Parent CO2 rows are not changed.
# Needs b3. Method: kaist/steel/README.md section 4.
################################################################################

add_steel_process_emissions <- function(data) {
  year_columns <- year_cols(data)

  cat("\n=== Iron and Steel Process Emissions (Coal|Feedstock x MT 2020 factor) ===\n")

  feed_var <- "Final Energy|Industry|Iron and Steel|Coal|Feedstock"
  co2_var  <- "Emissions|CO2|Energy|Demand|Industry|Iron and Steel"
  proc_var <- "Emissions|GHGs|Non-Energy|Industrial Process|Iron and Steel"

  if (!any(data$Variable == feed_var) || !any(data$Variable == co2_var)) {
    cat("Skipped steel process split (needs", feed_var, "from b3 and", co2_var, ")\n")
    return(data)
  }

  ref <- mt_steel_reference_2020()
  proc_factor <- ref$process_co2 / ref$coal_feedstock
  cat(sprintf("factor = MT 2020 process %.3f Mt / Coal|Feedstock %.1f ktoe = %.5f Mt CO2/ktoe (source: %s)\n",
              ref$process_co2, ref$coal_feedstock, proc_factor, ref$source))

  # EJ -> ktoe factor from kaist/unit_table.R
  if (!exists("unit_table")) source(file.path(getwd(), "kaist/unit_table.R"))
  ej_to_ktoe <- unit_table$factor[unit_table$from == "EJ/yr" & unit_table$to == "ktoe/yr"][1]

  new_rows <- list()
  max_resid <- 0
  for (scen in unique(data$Scenario)) {
    fi <- which(data$Variable == feed_var & data$Scenario == scen)
    ci <- which(data$Variable == co2_var & data$Scenario == scen)
    if (length(fi) == 0 || length(ci) == 0) next
    if (data$Unit[fi[1]] != "EJ/yr" || data$Unit[ci[1]] != "Mt CO2/yr") {
      stop("b6: unexpected units: ", feed_var, " = ", data$Unit[fi[1]],
           ", ", co2_var, " = ", data$Unit[ci[1]])
    }

    feed <- as.numeric(data[fi[1], year_columns]); feed[is.na(feed)] <- 0
    co2  <- as.numeric(data[ci[1], year_columns]); co2[is.na(co2)] <- 0
    process <- feed * ej_to_ktoe * proc_factor
    energy  <- co2 - process

    if (any(energy < 0)) {
      cat(sprintf("Warning: %s energy CO2 goes negative after the split in %s (min %.3f Mt)\n",
                  scen, paste(year_columns[energy < 0], collapse = ","), min(energy)))
    }

    proc_row <- data[ci[1], ]
    proc_row$Variable <- proc_var
    proc_row[, year_columns] <- as.list(process)
    new_rows[[length(new_rows) + 1]] <- proc_row

    data[ci[1], year_columns] <- as.list(energy)
    max_resid <- max(max_resid, abs(energy + process - co2))
  }

  if (length(new_rows) > 0) {
    data <- rbind(data, bind_rows(new_rows))
  }
  cat(sprintf("Created %s for %d scenario(s); energy + process = original CO2 (max resid %.2e)\n",
              proc_var, length(new_rows), max_resid))

  data
}
