################################################################################
# Step 1: Generate GCAM Report (Query Database)
#
# PURPOSE:
#   Query the GCAM BaseX database(s) and write the base report files.
#   Outputs (paths set in config.R):
#     {output_dir}/{run_name}.xlsx / .csv        - GCAM report (all regions)
#     {output_dir}/{run_name}_project_*.dat       - rgcam project (used by step2)
#   With scenario_jobs in the settings file (one BaseX DB per job) each job keeps
#   its own {run_name}_{label}.* report and .dat; the merged files above are
#   built from them at the end so step2 sees one report and one project.
#
# PREREQUISITES:
#   1. The built package data, data/*_v{version}.rda. They are gitignored; build
#      them with inst/extdata/saveDataFiles_GCAM{version}.R (or copy them from
#      an upstream checkout). KAIST overrides are applied on top at runtime.
#   2. Open a fresh R session before running this script.
#
# TROUBLESHOOTING:
#   - Mapping error ("Some rows in the left dataset do not have matching
#     keys"): add the missing rows to kaist_overrides in
#     kaist/core/functions.R, then rerun with reuse_dat (below) so the
#     queries are not redone.
#   - "Database does not exist" error: see kaist/core/rgcam_patch.R.
#
# NEXT STEP: kaist/kmip/step2_process_data.R
################################################################################

########## Load configuration ##########
source(file.path(getwd(), "kaist/core/config.R"))
jobs <- step1_jobs()
########################################

########## Project files (.dat) ##########
# generate_report() always writes a new .dat to {db_path}/{db_name}_{prj_name}
# (see R/main.R::create_project), so we pass a basename and move the file into
# output_dir afterwards.
#
# To REUSE an existing .dat (skips the BaseX queries, e.g. after a mapping
# error), give its absolute path per job label, e.g.
#   reuse_dat <- c(Ref_u0909 = "C:/.../reports_u0909_Ref_u0909_project_20261004_180000.dat")
# Jobs not listed are queried from the database as usual.
reuse_dat <- NULL
run_stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
##########################################

########## Libraries ##########
devtools::load_all(".", reset = TRUE)
# KAIST data overrides, in memory only (kaist/core/functions.R::patch_gcam_data).
# Must run after load_all.
patch_gcam_data(paste0("v", version_number))
# Project hook: a settings file may define patch_project_data(version) for data
# overrides that belong to one project only (e.g. kaist/ktraces/functions.R).
if (exists("patch_project_data", mode = "function")) {
  patch_project_data(paste0("v", version_number))
  inject_kaist_data()
}
library(dplyr)
library(rgcam)
library(tidyr)
library(readxl)

# rgcam fix for BaseX 9.5+ (needed on this machine; harmless otherwise).
source(file.path(getwd(), "kaist/core/rgcam_patch.R"))
###############################

########## Generate report, one generate_report() call per job ##########
multi <- nrow(jobs) > 1
job_results <- list()

for (i in seq_len(nrow(jobs))) {
  job       <- jobs[i, ]
  scen      <- unlist(job$scenario)
  job_name  <- if (multi) paste0(run_name, "_", job$label) else run_name
  prj_basename <- paste0(job_name, "_project_", run_stamp, ".dat")

  if (!is.null(reuse_dat) && job$label %in% names(reuse_dat)) {
    prj_name <- reuse_dat[[job$label]]          # absolute path: loaded, not queried
  } else {
    prj_name <- prj_basename
  }

  cat(sprintf("\n########## step1 job %d/%d: %s (db = %s, scenario = %s) ##########\n",
              i, nrow(jobs), job$label, job$db, paste(scen, collapse = ", ")))

  generate_report(
    db_path           = db_path,
    db_name           = job$db,
    scenarios         = scen,
    prj_name          = prj_name,
    final_year        = final_year,
    GCAM_version      = paste0("v", version_number),
    desired_variables = desired_variables,
    desired_regions   = desired_regions,
    ignore            = get0("ignore_markets", ifnotfound = NULL),
    save_output       = TRUE,
    output_file       = file.path(output_dir, job_name),
    launch_ui         = FALSE
  )

  # Move the freshly created .dat next to its report.
  if (identical(prj_name, prj_basename)) {
    created_dat <- file.path(db_path, paste(job$db, prj_basename, sep = "_"))
    moved_dat   <- file.path(output_dir, prj_basename)
    if (file.exists(created_dat)) {
      file.rename(created_dat, moved_dat)
      prj_name <- moved_dat
      # Project queries (settings: project_queries) go into the saved project.
      if (exists("project_queries")) {
        conn <- rgcam::localDBConn(db_path, job$db, maxMemory = "8g")
        add_kaist_queries(conn, moved_dat, scen, desired_regions, project_queries)
      }
      check_policy_markets(moved_dat, get0("ignore_markets", ifnotfound = NULL))
    } else {
      warning("Expected .dat not found at ", created_dat, " -- skipped the move.")
    }
  }
  job_results[[job$label]] <- list(report = file.path(output_dir, paste0(job_name, ".xlsx")),
                                   dat = prj_name)
}
##########################################################################

########## Merge per-job outputs into the files step2 expects ##########
if (multi) {
  source(file.path(getwd(), "kaist/core/tools/step1_merge.R"))
}
########################################################################

cat("\n=== Step 1 Complete ===\n")
for (lb in names(job_results)) {
  cat(sprintf("  %-12s report:  %s\n  %-12s project: %s\n",
              lb, job_results[[lb]]$report, "", job_results[[lb]]$dat))
}
cat("Merged report:", file.path(output_dir, paste0(run_name, ".xlsx")), "\n")
cat("Next: kaist/kmip/step2_process_data.R\n")
########################################
