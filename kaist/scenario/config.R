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
scenario_output_dir <- file.path(scenario_dir, "reports_u0909")

scenario_jobs <- data.frame(
  db = c("u0909r", "u0909n"),
  scenario = c("KAIST_9_ref_u0909", "KAIST_9_NZ_u0909"),
  label = c("Ref_u0909", "NZ_u0909"),
  stringsAsFactors = FALSE
)

if (!dir.exists(scenario_output_dir)) {
  dir.create(scenario_output_dir, recursive = TRUE)
}
