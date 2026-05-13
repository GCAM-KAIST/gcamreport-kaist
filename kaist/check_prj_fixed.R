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
