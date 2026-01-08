################################################################################
# Step 1: Generate GCAM Report (Query Database)
#
# PURPOSE:
#   Query GCAM database and generate base report data using gcamreport package.
#   This is the first step that runs database queries and creates .prj file.
#
# WHAT THIS SCRIPT DOES:
#   - Connect to GCAM database (BaseX)
#   - Run queries for specified variables
#   - Generate report CSV/Excel files
#   - Save query results to .prj file (for reuse in step2)
#
# PREREQUISITES:
#   1. Ensure inst/extdata/mappings/GCAM7.0/variables_functions_mapping.csv
#      and inst/extdata/saveDataFiles_GCAM7.0.R are up to date
#      (See kaist/examples/saveDataFiles_GCAM7.0_example.R for reference)
#   2. Source R/functions.R first (required for saveDataFiles to work)
#   3. Run inst/extdata/saveDataFiles_GCAM7.0.R to prepare data files
#   4. Open a NEW R terminal and run this script
#   (See kaist/Modify_Mapping_Template_Tutorial.Rmd for detailed instructions)
#
# TROUBLESHOOTING:
#   - MAPPING ERROR: Fix mapping files, then re-run with existing .prj
#     (uncomment "Option 2" below and set prj_name to existing file)
#   - "Database does not exist" ERROR: See rgcam_patch.R
#
# OUTPUT:
#   - {output_prefix}.xlsx: GCAM report (all regions)
#   - projects/{project_name}/project_*.dat: Query results for step2
#
# NEXT STEP:
#   - kaist/step2_process_data.R
#
################################################################################

########## Load Configuration ##########
source(file.path(getwd(), "kaist/config.R"))
########################################

########## Project File (.prj) ##########
# Option 1: New file - queries database and creates new .prj
prj_name <- file.path(project_dir, paste0("project_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".dat"))

# Option 2: Existing file - skips queries, uses cached data
#   Use when re-running after MAPPING error (queries already done)
# prj_name <- file.path(project_dir, "project_20251230_225347.dat")
#########################################

########## Libraries ##########
devtools::load_all(".", reset = TRUE)
library(dplyr)
library(rgcam)
library(tidyr)
library(readxl)

# Apply rgcam patch for BaseX compatibility
source(file.path(getwd(), "kaist/rgcam_patch.R"))
################################

########## Generate Report ##########
target_var <- c(
  "Emissions|CH4*", "Emissions|N2O*", "Emissions|CO2*",
  "Primary Energy*", "Final Energy*",
  "Secondary Energy*", "Capacity*",
  "Price|Primary Energy*", "Price|Secondary Energy*",
  "Investment*", "Carbon Capture*", "Production*", "Capital Cost*", "Price|Carbon"
)

generate_report(
  db_path = db_path,
  db_name = db_name,
  # scenarios = scenarios,
  prj_name = prj_name,
  final_year = final_year,
  GCAM_version = paste0("v", version_number),
  desired_variables = target_var,
  save_output = TRUE,
  desired_regions = "All",  # Or: c("South Korea", "Japan")
  output_file = file.path(output_dir, output_prefix),
  launch_ui = FALSE
)

cat("\n=== Step 1 Complete ===\n")
cat("Project file:", prj_name, "\n")
cat("Output:", file.path(output_dir, paste0(output_prefix, ".xlsx")), "\n")
cat("Next: Run kaist/step2_process_data.R\n")
######################################
