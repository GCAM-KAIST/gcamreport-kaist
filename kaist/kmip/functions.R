################################################################################
# KMIP project data overrides. kaist/core/functions.R holds the mapping rows that
# every gcam-kaist9 database needs; this file holds rows that only some KMIP
# runs need. A settings file that needs them sources this file (see
# kaist/kmip/config/nmsf2_k9l.R); the step1 project hook then calls
# patch_project_data() after patch_gcam_data().
################################################################################

kmip_overrides <- list(
  "v9.1" = list(
    map_rows = list(
      # NMSF2 runs (gcam-kaist9 PR #6): the gases linked to GHG_Kor (LULUCF adder,
      # international credits, bunker adjustments) appear in "prices of all
      # markets". They are policy bookkeeping and must not become fuel prices.
      energy_price_map = list(
        rows = tibble::tibble(
          market = c("CO2_LULUCF_adj", "CO2_intl_credit", "CO2_bunker_adj",
                     "CH4_bunker_adj", "N2O_bunker_adj"),
          unit_conv = 1,
          var = "NoReported"
        ),
        key = c("market", "var")
      )
    )
  )
)

patch_project_data <- function(version) patch_gcam_data(version, kmip_overrides, label = "KMIP")
