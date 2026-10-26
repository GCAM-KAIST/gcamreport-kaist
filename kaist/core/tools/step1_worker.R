################################################################################
# step1_worker: query ONE scenario into {run_name}_{label}.* outputs.
#
# Usage:  Rscript kaist/core/tools/step1_worker.R <scenario>
# Run one worker per scenario in parallel (each BaseX query is single-
# threaded), then combine with kaist/core/tools/step1_merge.R.
# With a scenario manifest the database and label are looked up from
# scenario_jobs; otherwise db_name from config.R and label = scenario.
#
# Each worker applies patch_gcam_data() in memory after load_all.
################################################################################

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("usage: Rscript kaist/core/tools/step1_worker.R <scenario>")
scen <- args[1]

source(file.path(getwd(), "kaist/core/config.R"))
label <- scen
if (exists("scenario_jobs")) {
  job <- scenario_jobs[scenario_jobs$scenario == scen | scenario_jobs$label == scen, ]
  if (nrow(job) != 1) stop("scenario '", scen, "' is not (uniquely) declared in scenario_jobs")
  db_name <- job$db
  scen    <- job$scenario
  label   <- job$label
}
run_name  <- paste0(run_name, "_", label)
scenarios <- scen
prj_basename <- paste0(run_name, "_project.dat")
prj_name     <- prj_basename

devtools::load_all(".", reset = TRUE)
patch_gcam_data(paste0("v", version_number))   # in memory, after load_all
# Project hook: a settings file may define patch_project_data(version) for data
# overrides that belong to one project only (e.g. kaist/ktraces/functions.R).
if (exists("patch_project_data", mode = "function")) {
  patch_project_data(paste0("v", version_number))
  inject_kaist_data()
}
library(dplyr)
library(rgcam)
library(tidyr)

source(file.path(getwd(), "kaist/core/rgcam_patch.R"))

generate_report(
  db_path           = db_path,
  db_name           = db_name,
  scenarios         = scenarios,
  prj_name          = prj_name,
  final_year        = final_year,
  GCAM_version      = paste0("v", version_number),
  desired_variables = desired_variables,
  desired_regions   = desired_regions,
  ignore            = get0("ignore_markets", ifnotfound = NULL),
  save_output       = TRUE,
  output_file       = file.path(output_dir, run_name),
  launch_ui         = FALSE
)

created_dat <- file.path(db_path, paste(db_name, prj_basename, sep = "_"))
if (file.exists(created_dat)) {
  file.rename(created_dat, file.path(output_dir, prj_basename))
}

# Project queries (settings: project_queries, a query xml such as
# kaist/kmip/queries/nmsf2_queries.xml) go into the saved project.
dat_path <- file.path(output_dir, prj_basename)
if (file.exists(dat_path)) {
  if (exists("project_queries")) {
    conn <- rgcam::localDBConn(db_path, db_name, maxMemory = "8g")
    add_kaist_queries(conn, dat_path, scenarios, desired_regions, project_queries)
  }
  check_policy_markets(dat_path, get0("ignore_markets", ifnotfound = NULL))
}

cat("\n=== step1_worker complete:", label, "===\n")
