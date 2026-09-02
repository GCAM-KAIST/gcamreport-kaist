################################################################################
# step1_merge: combine per-scenario step1_worker outputs into the single
# {run_name}.xlsx and {run_name}_project_merged.dat that step2 expects.
#
# Usage: Rscript kaist/tools/step1_merge.R   (scenarios come from config.R)
################################################################################

source(file.path(getwd(), "kaist/config.R"))
suppressMessages({
  library(dplyr)
  library(readxl)
  library(writexl)
  library(rgcam)
})

per_run <- paste0(run_name, "_", scenarios)

# xlsx: row-bind the per-scenario reports (same columns)
xlsx_paths <- file.path(output_dir, paste0(per_run, ".xlsx"))
missing <- xlsx_paths[!file.exists(xlsx_paths)]
if (length(missing) > 0) stop("missing worker outputs: ", paste(missing, collapse = ", "))
data <- bind_rows(lapply(xlsx_paths, read_excel))
write_xlsx(data, file.path(output_dir, paste0(run_name, ".xlsx")))
cat("Merged xlsx:", nrow(data), "rows,", length(unique(data$Scenario)), "scenarios\n")

# .dat: merge the rgcam projects (step2 matches ^{run_name}_project_.*\.dat$)
prjs <- lapply(file.path(output_dir, paste0(per_run, "_project.dat")), loadProject)
merged_path <- file.path(output_dir, paste0(run_name, "_project_merged.dat"))
if (file.exists(merged_path)) file.remove(merged_path)
merged <- mergeProjects(merged_path, prjs, clobber = TRUE, saveProj = TRUE)
cat("Merged project:", paste(listScenarios(merged), collapse = ", "), "\n")

cat("\n=== step1_merge complete ===\n")
