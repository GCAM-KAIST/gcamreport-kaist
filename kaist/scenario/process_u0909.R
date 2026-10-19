source(file.path(getwd(), "kaist-pj", "scenario", "config.R"))
devtools::load_all(".", reset = TRUE)

GCAM_version <- scenario_gcam_version
stopifnot(GCAM_version %in% gcamreport::available_GCAM_versions)

for (i in seq_len(nrow(scenario_jobs))) {
  job <- scenario_jobs[i, ]
  stopifnot(file.exists(file.path(scenario_dir, job$db, "tbl.basex")))

  message("처리 시작: ", job$scenario)

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

  message("처리 완료: ", job$scenario)
}

message("두 시나리오 후처리 완료")
