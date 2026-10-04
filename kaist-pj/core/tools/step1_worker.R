# [2026-10-04: Claude code] manifest-aware (db/label lookup), ignore_markets, gcamreport_patch.R; paths kaist/ -> kaist-pj/.
################################################################################
# step1_worker: query ONE scenario into {run_name}_{label}.* outputs.
#
# Usage:  Rscript kaist-pj/core/tools/step1_worker.R <scenario>
# Run one worker per scenario in parallel (each BaseX query is single-
# threaded), then combine with kaist-pj/core/tools/step1_merge.R.
# With a scenario manifest the database and label are looked up from
# scenario_jobs; otherwise db_name from config.R and label = scenario.
#
# NOTE: run patch_gcam_data() ONCE before launching workers (the parallel
# driver does this); workers skip it so 8 processes do not rewrite the same
# data/*.rda files concurrently.
################################################################################

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("usage: Rscript kaist-pj/core/tools/step1_worker.R <scenario>")
scen <- args[1]

source(file.path(getwd(), "kaist-pj/core/config.R"))
label <- scen
if (exists("scenario_jobs")) {
  job <- scenario_jobs[scenario_jobs$scenario == scen | scenario_jobs$label == scen, ]
  if (nrow(job) != 1) stop("scenario '", scen, "' is not (uniquely) declared in kaist-pj/scenario/config.R")
  db_name <- job$db
  scen    <- job$scenario
  label   <- job$label
}
run_name  <- paste0(run_name, "_", label)
scenarios <- scen
prj_basename <- paste0(run_name, "_project.dat")
prj_name     <- prj_basename

devtools::load_all(".", reset = TRUE)
library(dplyr)
library(rgcam)
library(tidyr)

source(file.path(getwd(), "kaist-pj/core/rgcam_patch.R"))
source(file.path(getwd(), "kaist-pj/core/gcamreport_patch.R"))

generate_report(
  db_path           = db_path,
  db_name           = db_name,
  scenarios         = scenarios,
  prj_name          = prj_name,
  final_year        = final_year,
  GCAM_version      = paste0("v", version_number),
  desired_variables = desired_variables,
  desired_regions   = desired_regions,
  ignore            = ignore_markets,
  save_output       = TRUE,
  output_file       = file.path(output_dir, run_name),
  launch_ui         = FALSE
)

created_dat <- file.path(db_path, paste(db_name, prj_basename, sep = "_"))
if (file.exists(created_dat)) {
  file.rename(created_dat, file.path(output_dir, prj_basename))
}

cat("\n=== step1_worker complete:", label, "===\n")
