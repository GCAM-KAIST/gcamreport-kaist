################################################################################
# KAIST helper functions
#
# Custom functions used by the kaist/ pipeline. Kept here (not in R/) so that
# the package source under R/ and inst/ stays identical to upstream gcamreport
# and can be synced with `git merge upstream/gcam-core` without conflicts.
#
# Sourced automatically from kaist/config.R, so every step file has these
# available after `source(".../kaist/config.R")`.
################################################################################

# available_variables_with_units --------------------------------------------
# Like gcamreport::available_variables(), but returns each variable together
# with its unit. Useful for saving a variable list to share with collaborators.
# Reads the bundled template_v7.x via the loaded gcamreport namespace, so it
# only works after devtools::load_all(".") in a step file.
available_variables_with_units <- function(print = TRUE, GCAM_version = "v7.1") {
  Internal_variable <- Variable <- Unit <- NULL

  av_var <- get(paste("template", GCAM_version, sep = "_"),
                envir = asNamespace("gcamreport")) %>%
    dplyr::filter(!is.na(Internal_variable) & Internal_variable != "") %>%
    dplyr::select(Variable, Unit) %>%
    dplyr::distinct()

  if (print) {
    for (i in seq_len(nrow(av_var))) {
      cat(av_var$Variable[i], " (", av_var$Unit[i], ")\n", sep = "")
    }
  }

  return(av_var)
}

# add_korea_cf --------------------------------------------------------------
# Append South Korea conventional capacity factors (KMIP reference values) to
# the upstream cf_rgn_v7.0 table. cf_rgn_v7.0 ships with renewables only; the
# step2 vintage-based capacity recalculation reads it as the per-region CF
# source, so the Korea overrides live here in one place instead of editing the
# upstream inst/extdata/saveDataFiles_GCAM7.0.R.
#
# Idempotent: drops any existing rows for the same (region, technology, year)
# before binding, so re-running step2 never double-adds.
add_korea_cf <- function(cf_rgn) {
  korea_cf <- tidyr::crossing(
    tibble::tribble(
      ~subsector,         ~stub.technology,              ~capacity.factor,
      # Coal
      "coal",             "coal (conv pul)",             0.635,
      "coal",             "coal (conv pul CCS)",         0.635,
      "coal",             "coal (IGCC)",                 0.635,
      "coal",             "coal (IGCC CCS)",             0.635,
      # Gas
      "gas",              "gas (CC)",                    0.50,
      "gas",              "gas (CC CCS)",                0.50,
      "gas",              "gas (steam/CT)",              0.50,
      # Hydro
      "hydro",            "hydro",                       0.084,
      # Nuclear (Gen_III_Korea is a Korea-only tech defined in cf_gcam)
      "nuclear",          "Gen_III",                     0.8144,
      "nuclear",          "Gen_III_Korea",               0.8144,
      "nuclear",          "Gen_II_LWR",                  0.8144,
      # Refined liquids (oil-fired)
      "refined liquids",  "refined liquids (CC)",        0.76,
      "refined liquids",  "refined liquids (CC CCS)",    0.76,
      "refined liquids",  "refined liquids (steam/CT)",  0.76,
      # Biomass
      "biomass",          "biomass (conv)",              0.80,
      "biomass",          "biomass (conv CCS)",          0.80,
      "biomass",          "biomass (IGCC)",              0.80,
      "biomass",          "biomass (IGCC CCS)",          0.80,
      # Solar CSP (with and without storage)
      "CSP",              "CSP",                         0.20,
      "CSP",              "CSP_storage",                 0.20
    ),
    year = c(2005, 2010, 2015, 2020, 2025, 2030, 2035, 2040,
             2045, 2050, 2055, 2060, 2070, 2080, 2090, 2100)
  ) %>%
    dplyr::mutate(
      region = "South Korea",
      supplysector = "electricity"
    )

  cf_rgn %>%
    dplyr::anti_join(korea_cf, by = c("region", "stub.technology", "year")) %>%
    dplyr::bind_rows(korea_cf)
}
