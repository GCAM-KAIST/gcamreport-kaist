################################################################################
# KAIST GCAM Report Configuration
#
# This file contains shared settings for all step files.
# Modify these values for your project, then source this file in each step.
#
# Usage in step files:
#   source(file.path(getwd(), "kaist/config.R"))
#
################################################################################

# === Project Settings ===
project_name <- "kmip2026"      # Project identifier (folder name)
output_prefix <- "kaist_report" # Output file prefix
target_region <- "South Korea"  # Region to process in step2

# === GCAM Database Settings ===
# Set this to your GCAM output database location
db_path <- "C:/GCAM/gcamreport/kmip"
db_name <- "DB26"

# === Year Range ===
start_year <- 2005
final_year <- 2050
version_number <- "7.0"

# === Derived Paths ===
# Project output directory
project_dir <- "C:/GCAM/gcamreport/kmip"
output_dir <- "C:/GCAM/gcamreport/kmip/DB26_output"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# KAIST data directory (coefficient files, etc.)
kaist_data_dir <- file.path(getwd(), "kaist/data")

# Model name for reports
model_name <- paste("GCAM", version_number)

cat("Config loaded: project =", project_name, ", output_dir =", output_dir, "\n")

# === Reference Scenario (optional) ===
# Used for vehicle capacity conversion ratio (step2)
# If not set, first available scenario is used
# ref_scenario <- "Ref_Con"

# === Template & Mapping Files ===
template_path <- file.path(output_dir, "KMIP2025_DB_final.xlsx")
mapping_path <- file.path(output_dir, "kmip_gcam_mapping_template.xlsx")
