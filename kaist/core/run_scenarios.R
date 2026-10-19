# [2026-10-04: Claude code] added patch_gcam_data() before load_all.
# [2026-10-19: Claude code] gcamreport_patch.R removed (as on main); the non-empty `ignore` keeps the upstream CO2 price filter safe.
################################################################################
# Run every scenario declared in kaist/scenario/config.R.
#
# Usage from the gcamreport package root:
#   Rscript kaist/core/run_scenarios.R
################################################################################

source(file.path(getwd(), "kaist", "scenario", "config.R"))
source(file.path(getwd(), "kaist", "core", "functions.R"))

# KAIST data overrides (v9.1 mapping rows) -- must run before load_all.
patch_gcam_data(scenario_gcam_version)

devtools::load_all(".", reset = TRUE)
source(file.path(getwd(), "kaist", "core", "rgcam_patch.R"))

GCAM_version <- scenario_gcam_version
stopifnot(GCAM_version %in% gcamreport::available_GCAM_versions)

for (i in seq_len(nrow(scenario_jobs))) {
  job <- scenario_jobs[i, ]
  db_file <- file.path(scenario_dir, job$db, "tbl.basex")
  if (!file.exists(db_file)) {
    stop("Scenario database is missing: ", db_file)
  }

  message("Starting scenario: ", job$scenario)
  generate_report(
    db_path = scenario_dir,
    db_name = job$db,
    prj_name = paste0(job$label, ".dat"),
    scenarios = job$scenario,
    GCAM_version = GCAM_version,
    ignore = scenario_ignore,   # must be non-empty: see ignore_markets in core/config.R
    final_year = scenario_final_year,
    desired_regions = "All",
    desired_variables = "All",
    save_output = TRUE,
    output_file = file.path(scenario_output_dir, job$label),
    launch_ui = FALSE
  )
  message("Finished scenario: ", job$scenario)
}

message("All declared scenarios completed.")
