# Run 7: Ref scenario with ALL fixes (original strict join), loading the rgcam project saved by run 1
# instead of re-querying the database. Error hook prints the ignore global and call stack.
setwd("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp")
devtools::load_all(".", reset = TRUE)
GCAM_version <- "v9.1"
db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
report_dir <- file.path(db_path, "reports_u0909")
options(error = quote({
  cat("\n=== ERROR HOOK ===\nignore.global at error: ", deparse(.myGlobals$ignore.global), "\n")
  if (exists("left_join_strict_details")) print(left_join_strict_details)
  calls <- sys.calls(); cat("call stack (last 12):\n"); print(tail(lapply(calls, function(x) deparse(x)[1]), 12))
  q(status = 1)
}))
generate_report(
  db_path = db_path, db_name = "u0909r",
  prj_name = file.path(db_path, "u0909r_Ref_u0909.dat"),
  scenarios = "KAIST_9_ref_u0909", GCAM_version = GCAM_version,
  ignore = "^bio-ceiling$", final_year = 2050,
  desired_regions = "All", desired_variables = "All",
  save_output = TRUE, output_file = file.path("C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad/verify", "Ref_verify"), launch_ui = FALSE
)
message("RUN7 DONE")
