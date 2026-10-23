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

# KAIST policy markets: not reported (gcamreport `ignore` argument)
kaist_ignore <- c("-ceiling", "_ceiling", "bio-ceiling", "coal-ceiling", "irnstl-ceiling", "irnstl_ceiling_EAF",
                  "dac-ceiling", "Generation-Ceiling", "Generation-Floor",
                  "CO2_Kor", "GHG_Kor", "rowbio-ceiling", "rowCO2")
# KAIST v9.1 mapping rows (kaist_overrides), added in memory only
patch_gcam_data(paste0("v", version_number))
t0 <- Sys.time()

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

# Reuse the saved project if there is one, else query the DB. generate_report()
# saves the .dat in dbs_dir before post-processing; move it to output_dir.
created_dat <- file.path(dbs_dir, paste(db, prj_basename, sep = "_"))
tryCatch(run_report(if (file.exists(existing_dat)) existing_dat else prj_basename),
         finally = if (file.exists(created_dat)) file.rename(created_dat, existing_dat))
# KAIST queries (kaist/core/queries/kaist_queries.xml), e.g. the NMSF2 LULUCF adjustment
add_kaist_queries(conn, existing_dat, sc$name, desired_regions)
cat("\n=== DONE", db, "in", format(Sys.time() - t0), "===\n")
