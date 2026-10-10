################################################################################
# Scenario manifest used by kaist-pj/core and scenario/process_u0909.R.
################################################################################

scenario_dir <- normalizePath(
  file.path(getwd(), "kaist-pj", "scenario"),
  winslash = "/",
  mustWork = FALSE
)

scenario_gcam_version <- "v9.1"
scenario_final_year <- 2050
scenario_ignore <- "^bio-ceiling$"
# K-TRACES SSP2 runs (2026-10-08): databases stay in the GCAM output folder
scenario_db_path <- "/home/jin-lee/gcam-v9.1/output"
scenario_output_dir <- "/home/jin-lee/ktraces/gcamreport_ssp2_ndc"

scenario_jobs <- data.frame(
  db = c("ssp2_ref", "ssp2_ndc_slow", "ssp2_ndc_fast"),
  scenario = c("SSP2-Ref", "SSP2-NDC-slow", "SSP2-NDC-fast"),
  label = c("Ref", "NDC_slow", "NDC_fast"),
  stringsAsFactors = FALSE
)

if (!dir.exists(scenario_output_dir)) {
  dir.create(scenario_output_dir, recursive = TRUE)
}
