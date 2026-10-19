# Checking the whether error happens to my setting too 
setwd("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp")
devtools::load_all(".", reset = TRUE)

GCAM_version <- "v9.1"
stopifnot(GCAM_version %in% gcamreport::available_GCAM_versions)

db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
report_dir <- file.path(db_path, "reports_u0909")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

jobs <- data.frame(
  db = c("u0909r", "u0909n"),
  scenario = c("KAIST_9_ref_u0909", "KAIST_9_NZ_u0909"),
  label = c("Ref_u0909", "NZ_u0909")
)

for (i in seq_len(nrow(jobs))) {
  job <- jobs[i, ]
  stopifnot(file.exists(file.path(db_path, job$db, "tbl.basex")))

  message("처리 시작: ", job$scenario)

  generate_report(
    db_path = db_path,
    db_name = job$db,
    prj_name = paste0(job$label, ".dat"),
    scenarios = job$scenario,
    GCAM_version = GCAM_version,
    # ignore = "^bio-ceiling$",
    final_year = 2050,
    desired_regions = "All",
    desired_variables = "All",
    save_output = TRUE,
    output_file = file.path(report_dir, job$label),
    launch_ui = FALSE
  )

  message("처리 완료: ", job$scenario)
}

message("두 시나리오 후처리 완료")
