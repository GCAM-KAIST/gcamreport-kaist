# Check project structure
library(tidyverse)
library(here)
library(rgcam)

source(file.path(here(), "kaist/config.R"))

# Load project file
prj_files <- list.files(file.path(here(), project_dir), pattern = ".*project_.*\\.dat$", full.names = TRUE)
cat("Project files found:", prj_files, "\n\n")

prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
cat("Using:", prj_file, "\n\n")

prj <- loadProject(prj_file)

cat("========== Project Structure ==========\n")
cat("Class:", class(prj), "\n")
cat("Names:", names(prj), "\n\n")

cat("========== Scenarios ==========\n")
scenarios <- listScenarios(prj)
print(scenarios)

cat("\n========== Try to get elec gen by gen tech ==========\n")
tryCatch({
  elec_gen <- getQuery(prj, "elec gen by gen tech")
  cat("Columns:", paste(names(elec_gen), collapse = ", "), "\n")
  cat("Rows:", nrow(elec_gen), "\n")
  cat("Sample:\n")
  elec_gen %>% filter(region == "South Korea") %>% head(10) %>% print()
}, error = function(e) {
  cat("Error:", e$message, "\n")
})
