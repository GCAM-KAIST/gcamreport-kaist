# Experiment B2: like run12 (no for loop) but `jobs`/`job` are defined and the arguments are passed as job$db / job$scenario / job$label.
# Original header: Experiment A: identical to run10 (debug.R on the LOAD path) except the for-loop is unrolled for the Ref job:
# no `jobs` data.frame, no `i`, no `job`. Everything else (setwd, load_all, GCAM_version, gcamreport:: check,
# report_dir, stopifnot, message) is kept verbatim.
setwd("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp")
devtools::load_all(".", reset = TRUE)

GCAM_version <- "v9.1"
stopifnot(GCAM_version %in% gcamreport::available_GCAM_versions)

db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
report_dir <- file.path(db_path, "reports_u0909")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

jobs <- data.frame(db = c("u0909r", "u0909n"), scenario = c("KAIST_9_ref_u0909", "KAIST_9_NZ_u0909"), label = c("Ref_u0909", "NZ_u0909"))
i <- 1L
job <- jobs[i, ]
stopifnot(file.exists(file.path(db_path, job$db, "tbl.basex")))
message("처리 시작: ", "KAIST_9_ref_u0909")
generate_report(
  db_path = db_path,
  db_name = job$db,
  prj_name = file.path(db_path, paste0(job$db, "_", job$label, ".dat")),
  scenarios = job$scenario,
  GCAM_version = GCAM_version,
  ignore = "^bio-ceiling$",
  final_year = 2050,
  desired_regions = "All",
  desired_variables = "All",
  save_output = TRUE,
  output_file = file.path("C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad/diag", paste0(job$label, "_run13")),
  launch_ui = FALSE
)
message("처리 완료: KAIST_9_ref_u0909")
message("두 시나리오 후처리 완료")
