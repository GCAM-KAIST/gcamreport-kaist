################################################################################
# Run every scenario declared in kaist-pj/scenario/config.R.
#
# Usage from the gcamreport package root:
#   Rscript kaist-pj/core/run_scenarios.R
################################################################################

source(file.path(getwd(), "kaist-pj", "scenario", "config.R"))
devtools::load_all(".", reset = TRUE)
source(file.path(getwd(), "kaist-pj", "core", "rgcam_patch.R"))

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
    ignore = scenario_ignore,
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
