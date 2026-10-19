# Run 19: NZ scenario, load path, debug.R's exact arguments (NO `ignore`), package with fixes 1-8.
# Expected: Price|Carbon / Revenue|Government restored (identical to run 6 output).
setwd("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp")
devtools::load_all(".", reset = TRUE)
stopifnot(exists("is_ignored")); cat("is_ignored(c('rowCO2','South KoreaCO2')) with NULL ignore ->", is_ignored(c("rowCO2","South KoreaCO2")), "\n")
GCAM_version <- "v9.1"
db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
out <- "C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad/verify2"; dir.create(out, showWarnings = FALSE, recursive = TRUE)
generate_report(db_path = db_path, db_name = "u0909n", prj_name = file.path(db_path, "u0909n_NZ_u0909.dat"),
  scenarios = "KAIST_9_NZ_u0909", GCAM_version = GCAM_version, final_year = 2050, desired_regions = "All",
  desired_variables = "All", save_output = TRUE, output_file = file.path(out, "NZ_noignore_fix8"), launch_ui = FALSE)
message("RUN19 DONE")
