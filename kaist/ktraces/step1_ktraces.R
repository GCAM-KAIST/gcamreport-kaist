################################################################################
# step1 for K-TRACES: one scenario (one BaseX DB) -> {run_name}_{label}.xlsx + .dat
#
# Same as kaist/core/tools/step1_worker.R, plus patch_project_data() after
# patch_gcam_data(): the K-TRACES industry extensions (kaist/ktraces/functions.R)
# are applied here and nowhere in kaist/core. Keep in step with step1_worker.R.
#
# Usage (from the repo root), one process per scenario, then the core merge:
#   export KAIST_CONFIG=kaist/ktraces/config/ssp2_ndc.R
#   Rscript kaist/ktraces/step1_ktraces.R SSP2-Ref
#   Rscript kaist/ktraces/step1_ktraces.R SSP2-NDC-slow
#   Rscript kaist/ktraces/step1_ktraces.R SSP2-NDC-fast
#   Rscript kaist/core/tools/step1_merge.R
################################################################################
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("usage: Rscript kaist/ktraces/step1_ktraces.R <scenario or label>")
scen <- args[1]

source(file.path(getwd(), "kaist/core/config.R"))
if (!exists("patch_project_data", mode = "function"))
  stop("KAIST_CONFIG must be a K-TRACES settings file (it sources kaist/ktraces/functions.R)")

job <- scenario_jobs[scenario_jobs$scenario == scen | scenario_jobs$label == scen, ]
if (nrow(job) != 1) stop("scenario '", scen, "' is not (uniquely) declared in scenario_jobs")
db_name   <- job$db
scen      <- job$scenario
label     <- job$label
run_name  <- paste0(run_name, "_", label)
prj_basename <- paste0(run_name, "_project.dat")

devtools::load_all(".", reset = TRUE)
patch_gcam_data(paste0("v", version_number))      # KAIST overrides, in memory
patch_project_data(paste0("v", version_number))   # K-TRACES overrides, in memory
inject_kaist_data()                               # push both into the loaded package
library(dplyr)
library(rgcam)
library(tidyr)
source(file.path(getwd(), "kaist/core/rgcam_patch.R"))

generate_report(
  db_path           = db_path,
  db_name           = db_name,
  scenarios         = scen,
  prj_name          = prj_basename,
  final_year        = final_year,
  GCAM_version      = paste0("v", version_number),
  desired_variables = desired_variables,
  desired_regions   = desired_regions,
  ignore            = get0("ignore_markets", ifnotfound = NULL),
  save_output       = TRUE,
  output_file       = file.path(output_dir, run_name),
  launch_ui         = FALSE
)

# generate_report() saves the .dat next to the DB; keep it with the report.
created_dat <- file.path(db_path, paste(db_name, prj_basename, sep = "_"))
if (file.exists(created_dat)) file.rename(created_dat, file.path(output_dir, prj_basename))
cat("\n=== step1_ktraces complete:", label, "===\n")
