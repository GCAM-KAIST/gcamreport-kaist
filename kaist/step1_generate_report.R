################################################################################
# Step 1: Generate GCAM Report (Query Database)
#
# PURPOSE:
#   Query the GCAM BaseX database and write the base report files.
#   Outputs (set in config.R):
#     {output_dir}/{run_name}.xlsx       - GCAM report (all regions)
#     {output_dir}/{run_name}_project_*.dat - rgcam project file (used by step2)
#
# PREREQUISITES:
#   1. Mappings in inst/extdata/mappings/GCAM7.0/ and the rda files generated
#      by inst/extdata/saveDataFiles_GCAM7.0.R must be up to date.
#   2. If you changed any mapping CSV, re-run saveDataFiles_GCAM7.0.R first.
#   3. Open a fresh R session before running this script.
#
# TROUBLESHOOTING:
#   - Mapping error: fix the mapping CSV, then rerun this script with
#     prj_name pointed at the existing .dat file (Option 2 below) so the
#     queries are not redone.
#   - "Database does not exist" error: see kaist/rgcam_patch.R.
#
# NEXT STEP: kaist/step2_process_data.R
################################################################################

########## Load configuration ##########
source(file.path(getwd(), "kaist/config.R"))
########################################

########## Project file (.dat) ##########
# generate_report() always writes a new .dat to
#   {db_path}/{db_name}_{prj_name}
# (see R/main.R::create_project line ~350). So for a new run we pass a
# basename only, and move the file to output_dir afterwards so DB25 / DB26
# outputs don't pile up in the kmip/ root.

# Option 1 (default): create a new .dat from fresh queries.
# We assign both prj_basename (used by the move block at the end) and
# prj_name (passed into generate_report).
prj_basename <- paste0(run_name, "_project_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".dat")
prj_name     <- prj_basename

# Option 2: reuse an existing .dat (skips the queries).
# Use after a mid-run error (e.g. mapping issue, missing rda) so you do not
# have to re-query the DB. Pass an absolute path; generate_report detects
# the file exists and just loads it.
# The .dat gcamreport just wrote (before the run errored out) lives at
#   {db_path}/{db_name}_{basename}
# Comment out Option 1 above and uncomment the line below when you want to
# reuse a .dat. Do not set prj_basename in this branch -- the move block at
# the end uses exists("prj_basename") to decide whether to move the file.
# prj_name <- "C:/GCAM/gcamreport/kmip/DB26_merge_test_project_20260513_150847.dat"
#########################################

########## Apply KAIST data overrides ##########
# Re-apply KAIST customizations to data/*.rda so the upstream
# inst/extdata/saveDataFiles_GCAM*.R can stay 100% unmodified.
# See kaist/functions.R::patch_gcam_data. Must run before load_all.
patch_gcam_data(paste0("v", version_number))
################################################

########## Libraries ##########
devtools::load_all(".", reset = TRUE)
library(dplyr)
library(rgcam)
library(tidyr)
library(readxl)

# Apply rgcam patch for BaseX 9.5+ if needed.
# source(file.path(getwd(), "kaist/rgcam_patch.R"))
###############################

########## Generate report ##########
# scenarios / desired_variables / desired_regions come from kaist/config.R
generate_report(
  db_path           = db_path,
  db_name           = db_name,
  scenarios         = scenarios,
  prj_name          = prj_name,
  final_year        = final_year,
  GCAM_version      = paste0("v", version_number),
  desired_variables = desired_variables,
  desired_regions   = desired_regions,
  save_output       = TRUE,
  output_file       = file.path(output_dir, run_name),
  launch_ui         = FALSE
)

########## Move .dat into output_dir ##########
# Only when we created a new project (Option 1). 
# Skip the move if the user pointed prj_name at an existing absolute path (Option 2).
if (exists("prj_basename") && identical(prj_name, prj_basename)) {
  created_dat <- file.path(db_path, paste(db_name, prj_basename, sep = "_"))
  moved_dat   <- file.path(output_dir, prj_basename)
  if (file.exists(created_dat)) {
    file.rename(created_dat, moved_dat)
    prj_name <- moved_dat
  } else {
    warning("Expected .dat not found at ", created_dat,
            " -- skipped the move.")
  }
}
##############################################

cat("\n=== Step 1 Complete ===\n")
cat("Project file:", prj_name, "\n")
cat("Output:", file.path(output_dir, paste0(run_name, ".xlsx")), "\n")
cat("Next: kaist/step2_process_data.R\n")
######################################
