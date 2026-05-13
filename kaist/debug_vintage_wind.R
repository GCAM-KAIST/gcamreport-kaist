# Debug vintage data for wind
library(tidyverse)
library(here)
library(rgcam)

source(file.path(here(), "kaist/config.R"))

# Load project
prj_files <- list.files(project_dir, pattern = ".*project_.*\\.dat$", full.names = TRUE)
prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
prj <- loadProject(prj_file)

# Get vintage query
elec_gen_vintage <- getQuery(prj, "elec gen by gen tech and cooling tech and vintage")

cat("========== Wind-related data in vintage query ==========\n")
elec_gen_vintage %>%
  filter(region == "South Korea", year == 2030) %>%
  filter(grepl("wind", output, ignore.case = TRUE) | grepl("wind", technology, ignore.case = TRUE)) %>%
  select(scenario, region, output, technology, year, value) %>%
  print(n = 50)

cat("\n========== All unique outputs for South Korea 2030 ==========\n")
elec_gen_vintage %>%
  filter(region == "South Korea", year == 2030) %>%
  distinct(output) %>%
  arrange(output) %>%
  print(n = 50)

cat("\n========== Checking tech_base derivation for wind ==========\n")
# Simulate the processing
wind_data <- elec_gen_vintage %>%
  filter(region == "South Korea", year == 2030) %>%
  filter(grepl("wind", output, ignore.case = TRUE) | grepl("wind", technology, ignore.case = TRUE))

if (nrow(wind_data) > 0) {
  wind_data %>%
    mutate(
      tech_base_from_output = gsub("elec_", "", output),
      tech_split = sapply(strsplit(technology, ","), `[`, 1)
    ) %>%
    select(output, technology, tech_base_from_output, tech_split, value) %>%
    print(n = 30)
}
