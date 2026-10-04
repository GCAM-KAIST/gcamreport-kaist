# [2026-10-04: Claude code] per-run names from step1_run_names(), newest .dat per run, also writes {run_name}.csv; paths kaist/ -> kaist-pj/.
################################################################################
# step1_merge: combine per-job step1 outputs into the single {run_name}.xlsx,
# {run_name}.csv and {run_name}_project_merged.dat that step2 expects.
#
# Per-job names come from config.R::step1_run_names():
#   {run_name}_{label}    with a scenario manifest (step1_generate_report.R)
#   {run_name}_{scenario} for the single-database step1_worker.R runs
# For each name the newest {name}_project*.dat in output_dir is merged.
#
# Usage: Rscript kaist-pj/core/tools/step1_merge.R
#        (also sourced by step1_generate_report.R when it ran several jobs)
################################################################################

if (!exists("step1_run_names")) source(file.path(getwd(), "kaist-pj/core/config.R"))
suppressMessages({
  library(dplyr)
  library(readxl)
  library(writexl)
  library(rgcam)
})

per_run <- step1_run_names()

# xlsx / csv: row-bind the per-job reports (same columns)
xlsx_paths <- file.path(output_dir, paste0(per_run, ".xlsx"))
missing <- xlsx_paths[!file.exists(xlsx_paths)]
if (length(missing) > 0) stop("missing step1 outputs: ", paste(missing, collapse = ", "))
data <- bind_rows(lapply(xlsx_paths, read_excel))
write_xlsx(data, file.path(output_dir, paste0(run_name, ".xlsx")))
write.csv(data, file.path(output_dir, paste0(run_name, ".csv")), row.names = FALSE)
cat("Merged report:", nrow(data), "rows,", length(unique(data$Scenario)), "scenario(s)\n")

# .dat: merge the rgcam projects (step2 matches ^{run_name}_project_.*\.dat$)
latest_dat <- function(rn) {
  cands <- list.files(output_dir, pattern = paste0("^", rn, "_project.*\\.dat$"), full.names = TRUE)
  if (length(cands) == 0) stop("no project .dat found for ", rn, " in ", output_dir)
  cands[order(file.mtime(cands), decreasing = TRUE)[1]]
}
prjs <- lapply(vapply(per_run, latest_dat, character(1)), loadProject)
merged_path <- file.path(output_dir, paste0(run_name, "_project_merged.dat"))
if (file.exists(merged_path)) file.remove(merged_path)
merged <- mergeProjects(merged_path, prjs, clobber = TRUE, saveProj = TRUE)
cat("Merged project:", paste(listScenarios(merged), collapse = ", "), "\n")

cat("\n=== step1_merge complete ===\n")
