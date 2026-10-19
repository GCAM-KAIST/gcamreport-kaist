# Step1 for GCAM-KAIST 9.1: one BaseX DB (one scenario) -> {db}.xlsx + {db}_project.dat
#
# DB layout: {db_path}/{db_name}/{db}/ (e.g. kmip/KAIST9_HLM/medium_nz/), one scenario per DB.
# Usage (from the repo root; settings from KAIST_CONFIG, default kaist/kmip/config/kaist9_hlm.R):
#   Rscript kaist/core/tools/kaist9/run_db.R medium_nz        # run
#   Rscript kaist/core/tools/kaist9/run_db.R medium_nz list   # only list scenarios
# Then: Rscript kaist/core/tools/kaist9/merge.R
args <- commandArgs(trailingOnly = TRUE)
db <- args[1]
mode <- if (length(args) > 1) args[2] else "run"

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(rgcam); library(dplyr); library(tidyr)
})
if (Sys.getenv("KAIST_CONFIG") == "") Sys.setenv(KAIST_CONFIG = "kaist/kmip/config/kaist9_hlm.R")
source("kaist/core/config.R")
source("kaist/core/rgcam_patch.R")
dbs_dir <- file.path(db_path, db_name)
stopifnot(dir.exists(file.path(dbs_dir, db)))

conn <- rgcam::localDBConn(dbs_dir, db, maxMemory = "8g")
sc <- rgcam::listScenariosInDB(conn)
cat("Scenarios in", db, ":\n"); print(as.data.frame(sc))
if (mode == "list") quit(save = "no")

prj_basename <- paste0(db, "_project.dat")
existing_dat <- file.path(output_dir, prj_basename)
prj_arg <- if (file.exists(existing_dat)) existing_dat else prj_basename

# KAIST policy markets: not reported (gcamreport `ignore` argument)
kaist_ignore <- c("-ceiling", "_ceiling", "bio-ceiling", "coal-ceiling", "irnstl-ceiling", "irnstl_ceiling_EAF",
                  "dac-ceiling", "Generation-Ceiling", "Generation-Floor",
                  "CO2_Kor", "GHG_Kor", "rowbio-ceiling", "rowCO2")
# Missing v9.1 mapping rows, added in memory only
source("kaist/core/tools/kaist9/runtime_patch_v9.1.R")
t0 <- Sys.time()

# Empty queries for South Korea break check_queries() or joins:
# add an empty district heat table, and give all-NA placeholder tables proper types
fill_empty_queries <- function(dat) {
  p <- rgcam::loadProject(dat)
  empty_schema <- list(
    "district heat production by subsector (fuel)" = tibble::tibble(
      Units = character(), scenario = character(), region = character(),
      sector = character(), subsector = character(), output = character(),
      year = double(), value = double())
  )
  changed <- FALSE
  for (s in rgcam::listScenarios(p)) for (q in names(empty_schema)) {
    if (is.null(p[[s]][[q]])) {
      p[[s]][[q]] <- empty_schema[[q]]; changed <- TRUE
      cat("fill_empty_queries: added empty", q, "for", s, "\n")
    }
  }
  for (s in rgcam::listScenarios(p)) for (q in names(p[[s]])) {
    d <- p[[s]][[q]]
    lg <- names(d)[vapply(d, is.logical, TRUE)]
    if (length(lg)) {
      for (cn in lg) d[[cn]] <- if (cn %in% c("year", "value")) as.double(d[[cn]]) else as.character(d[[cn]])
      p[[s]][[q]] <- d; changed <- TRUE
      cat("fill_empty_queries: typed NA columns in", q, ":", paste(lg, collapse = ","), "\n")
    }
  }
  if (changed) rgcam::saveProject(p, file = dat)
}

run_report <- function(prj) {
  generate_report(
    db_path           = dbs_dir,
    db_name           = db,
    prj_name          = prj,
    scenarios         = sc$name,
    final_year        = final_year,
    GCAM_version      = paste0("v", version_number),
    desired_variables = desired_variables,
    desired_regions   = desired_regions,
    ignore            = kaist_ignore,
    save_output       = TRUE,
    output_file       = file.path(output_dir, db),
    launch_ui         = FALSE
  )
}

if (!file.exists(existing_dat)) {
  # First pass queries the DB; the .dat is saved before post-processing
  res <- tryCatch(run_report(prj_basename), error = function(e) e)
  created_dat <- file.path(dbs_dir, paste(db, prj_basename, sep = "_"))
  if (file.exists(created_dat)) file.rename(created_dat, existing_dat)
  if (!inherits(res, "error")) { cat("\n=== DONE", db, "in", format(Sys.time() - t0), "===\n"); quit(save = "no") }
  cat("First pass error (expected for empty queries):", conditionMessage(res), "\n")
}
fill_empty_queries(existing_dat)
run_report(existing_dat)
cat("\n=== DONE", db, "in", format(Sys.time() - t0), "===\n")
