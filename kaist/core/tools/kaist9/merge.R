# Merge per-DB step1 outputs into {run_name}.xlsx/.csv + {run_name}_project_merged.dat.
# Scenario names become the DB folder names (high_ref, medium_nz, ...).
# Usage (from the repo root): Rscript kaist/core/tools/kaist9/merge.R
suppressMessages({ library(dplyr); library(readxl); library(writexl); library(rgcam) })
if (Sys.getenv("KAIST_CONFIG") == "") Sys.setenv(KAIST_CONFIG = "kaist/kmip/config/kaist9_hlm.R")
source("kaist/core/config.R")
dbs <- scenarios
ok <- dbs[file.exists(file.path(output_dir, paste0(dbs, ".xlsx"))) &
          file.exists(file.path(output_dir, paste0(dbs, "_project.dat")))]
cat("merging:", paste(ok, collapse = ", "), "\nmissing:", paste(setdiff(dbs, ok), collapse = ", "), "\n")

data <- bind_rows(lapply(ok, function(d) {
  x <- read_excel(file.path(output_dir, paste0(d, ".xlsx")))
  cat(d, "<-", paste(unique(x$Scenario), collapse = ";"), "\n")
  x$Scenario <- d
  x
}))
write_xlsx(data, file.path(output_dir, paste0(run_name, ".xlsx")))
write.csv(data, file.path(output_dir, paste0(run_name, ".csv")), row.names = FALSE)

# .dat: rename scenario keys and scenario columns to the DB name
prjs <- lapply(ok, function(d) {
  p <- loadProject(file.path(output_dir, paste0(d, "_project.dat")))
  s <- listScenarios(p); stopifnot(length(s) == 1)
  q <- lapply(p[[s]], function(t) { if ("scenario" %in% names(t)) t$scenario <- d; t })
  attributes(q) <- attributes(p[[s]]); names(q) <- names(p[[s]])
  np <- p; np[[s]] <- NULL; np[[d]] <- q
  np
})
dat <- file.path(output_dir, paste0(run_name, "_project_merged.dat"))
if (file.exists(dat)) file.remove(dat)
merged <- mergeProjects(dat, prjs, clobber = TRUE, saveProj = TRUE)
stopifnot(setequal(listScenarios(merged), unique(data$Scenario)))
cat("rows:", nrow(data), " scenarios:", paste(listScenarios(merged), collapse = ", "), "\n")
