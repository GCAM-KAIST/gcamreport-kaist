################################################################################
# Step 1 (pj-test): Generate GCAM Report (Query Database)
#
# PURPOSE:
#   Query the GCAM BaseX database and write the base report files.
#   Outputs (set in config.R):
#     {output_dir}/{run_name}.xlsx          - GCAM report (all regions)
#     {output_dir}/{run_name}_project_*.dat - rgcam project file (used by step2)
#
# HOW TO RUN (either):
#   a) source("kaist/core/pj-test/run_pjtest.R"); pjtest_run("report")
#   b) from the repo root:  Rscript kaist/core/pj-test/step1_generate_report.R
#
# PREREQUISITES:
#   1. data/*_v<version>.rda built (step0_build_data.R; automatic when
#      build_data_if_missing = TRUE in config.R).
#   2. Open a fresh R session before running this script.
#
# TROUBLESHOOTING:
#   - "Database does not exist or is invalid": set apply_rgcam_patch <- TRUE
#     in config.R (see rgcam_patch.R).
#   - Mapping error mid-run: point prj_name at the .dat already written
#     (Option 2 below) so the queries are not redone.
#
# NEXT STEP: kaist/kmip/step2_process_data.R (edit it to source this config)
################################################################################

########## Load configuration ##########
source(file.path(getwd(), "kaist/core/pj-test/config.R"))
########################################

########## Build data/*.rda if missing ##########
# data/ is gitignored; a fresh clone has nothing there.
rda_needed <- file.path("data", c("available_GCAM_versions.rda",
                                  paste0("template_v", version_number, ".rda")))
if (!all(file.exists(rda_needed))) {
  if (isTRUE(build_data_if_missing)) {
    cat("data/*.rda missing -> running step0_build_data.R\n")
    source(file.path(getwd(), pjtest_dir, "step0_build_data.R"))
  } else {
    stop("Missing built data: ", paste(rda_needed[!file.exists(rda_needed)], collapse = ", "),
         "\nRun kaist/core/pj-test/step0_build_data.R first.")
  }
}
#################################################

########## Project file (.dat) ##########
# generate_report() always writes a new .dat to {db_path}/{db_name}_{prj_name}
# (R/main.R::create_project). We pass a basename, then move the file to
# output_dir afterwards.

# Option 1 (default): create a new .dat from fresh queries.
prj_basename <- paste0(run_name, "_project_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".dat")
prj_name     <- prj_basename

# Option 2: reuse an existing .dat (skips the queries). Comment out Option 1
# and give an absolute path. Do not set prj_basename in this branch.
# prj_name <- file.path(output_dir, "pjtest_v8.2_project_YYYYMMDD_HHMMSS.dat")
#########################################

########## Apply KAIST data overrides ##########
# Off for the stock release DB (see apply_kaist_patch in config.R).
if (isTRUE(apply_kaist_patch)) {
  patch_gcam_data(paste0("v", version_number))
} else {
  cat("apply_kaist_patch = FALSE -> data/*.rda left as built from upstream mappings\n")
}
################################################

########## Libraries ##########
devtools::load_all(".", reset = TRUE)
library(dplyr)
library(rgcam)
library(tidyr)
library(readxl)

if (isTRUE(apply_rgcam_patch)) {
  source(file.path(getwd(), pjtest_dir, "rgcam_patch.R"))
}
###############################

########## Generate report ##########
t0 <- Sys.time()
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
cat(sprintf("generate_report finished in %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

########## Move .dat into output_dir ##########
if (exists("prj_basename") && identical(prj_name, prj_basename)) {
  created_dat <- file.path(db_path, paste(db_name, prj_basename, sep = "_"))
  moved_dat   <- file.path(output_dir, prj_basename)
  if (file.exists(created_dat)) {
    file.rename(created_dat, moved_dat)
    prj_name <- moved_dat
  } else {
    warning("Expected .dat not found at ", created_dat, " -- skipped the move.")
  }
}
##############################################

cat("\n=== Step 1 Complete ===\n")
cat("Project file:", prj_name, "\n")
cat("Output:", file.path(output_dir, paste0(run_name, ".xlsx")), "\n")
cat("Next: kaist/kmip/step2_process_data.R\n")
######################################
