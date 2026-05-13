# Check vintage query structure
library(tidyverse)
library(here)
library(rgcam)

source(file.path(here(), "kaist/config.R"))

# Load project file
prj_files <- list.files(file.path(here(), project_dir), pattern = ".*project_.*\\.dat$", full.names = TRUE)
prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
prj <- loadProject(prj_file)

# Get vintage query
elec_gen_vintage <- getQuery(prj, "elec gen by gen tech and cooling tech and vintage")

cat("========== Vintage Query Structure ==========\n")
cat("Columns:", paste(names(elec_gen_vintage), collapse = ", "), "\n\n")

cat("========== Sample data (South Korea, 2030) ==========\n")
elec_gen_vintage %>%
  filter(region == "South Korea", year == 2030) %>%
  head(20) %>%
  print()

cat("\n========== Unique outputs ==========\n")
unique(elec_gen_vintage$output) %>% sort() %>% print()

cat("\n========== Technology format examples ==========\n")
elec_gen_vintage %>%
  filter(region == "South Korea", year == 2030) %>%
  select(output, technology) %>%
  distinct() %>%
  head(30) %>%
  print()
