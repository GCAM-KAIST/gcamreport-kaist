# Project file inspection bundle
#
# Combined from earlier one-off scripts that load the latest .dat project
# file and explore its structure. Useful for sanity-checking the output of
# step1 (rgcam project file).
#
# Sections:
#  1. List available queries in the project (was: check_available_queries.R)
#  2. Project structure walk-through (was: check_prj_structure.R)
#  3. Project structure with absolute paths (was: check_prj_fixed.R)

# ============================================================
# Section 1: list available queries
# ============================================================
# Check available queries
library(tidyverse)
library(here)
library(rgcam)

source(file.path(here(), "kaist/config.R"))

# Load project file
prj_files <- list.files(file.path(here(), project_dir), pattern = ".*project_.*\\.dat$", full.names = TRUE)
prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
prj <- loadProject(prj_file)

cat("========== Available Queries ==========\n")
queries <- listQueries(prj)
print(queries)

cat("\n========== Queries containing 'vintage' or 'elec' ==========\n")
queries[grepl("vintage|elec", queries, ignore.case = TRUE)] %>% print()

# ============================================================
# Section 2: project structure walk-through
# ============================================================
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

# ============================================================
# Section 3: project structure with absolute paths
# ============================================================
# Check project structure - fixed paths
library(tidyverse)
library(here)
library(rgcam)

source(file.path(here(), "kaist/config.R"))

# Use absolute path from config
prj_files <- list.files(project_dir, pattern = ".*project_.*\\.dat$", full.names = TRUE)
cat("Project files found:", prj_files, "\n\n")

if (length(prj_files) > 0) {
  prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
  cat("Using:", prj_file, "\n\n")

  prj <- loadProject(prj_file)

  cat("========== Scenarios ==========\n")
  scenarios <- listScenarios(prj)
  print(scenarios)

  cat("\n========== Available Queries ==========\n")
  if (length(scenarios) > 0) {
    queries <- listQueries(prj, scenarios[1])
    print(queries)

    cat("\n========== Vintage-related queries ==========\n")
    vintage_queries <- queries[grepl("vintage", queries, ignore.case = TRUE)]
    print(vintage_queries)
  }
}
