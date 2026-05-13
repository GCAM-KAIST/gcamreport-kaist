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
