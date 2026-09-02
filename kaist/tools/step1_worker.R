################################################################################
# step1_worker: query ONE scenario into {run_name}_{scenario}.* outputs.
#
# Usage:  Rscript kaist/tools/step1_worker.R <scenario>
# Run one worker per scenario in parallel (each BaseX query is single-
# threaded), then combine with kaist/tools/step1_merge.R.
#
# NOTE: run patch_gcam_data() ONCE before launching workers (the parallel
# driver does this); workers skip it so 8 processes do not rewrite the same
# data/*.rda files concurrently.
################################################################################

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("usage: Rscript kaist/tools/step1_worker.R <scenario>")
scen <- args[1]

source(file.path(getwd(), "kaist/config.R"))
run_name  <- paste0(run_name, "_", scen)
scenarios <- scen
prj_basename <- paste0(run_name, "_project.dat")
prj_name     <- prj_basename

devtools::load_all(".", reset = TRUE)
library(dplyr)
library(rgcam)
library(tidyr)

source(file.path(getwd(), "kaist/rgcam_patch.R"))

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

created_dat <- file.path(db_path, paste(db_name, prj_basename, sep = "_"))
if (file.exists(created_dat)) {
  file.rename(created_dat, file.path(output_dir, prj_basename))
}

cat("\n=== step1_worker complete:", scen, "===\n")
