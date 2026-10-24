################################################################################
# Run settings: ssp2_ndc (K-TRACES; GCAM-KAIST 9.1 SSP2-Ref / SSP2-NDC-slow /
# SSP2-NDC-fast, one BaseX DB per scenario, DBs left in the GCAM output folder).
# Used through the loader: KAIST_CONFIG=kaist/ktraces/config/ssp2_ndc.R Rscript <script>
#   step1:    Rscript kaist/ktraces/step1_ktraces.R <scenario>  (x3), then
#             Rscript kaist/core/tools/step1_merge.R
#   workbook: Rscript kaist/ktraces/build_ktraces_workbook.R
################################################################################

# === Run name (output prefix) =================================================
run_name <- "ssp2_ndc"

# === GCAM databases ===========================================================
# One generate_report() call per row (see step1_jobs() in kaist/core/config.R).
db_path <- "/home/jin-lee/gcam-v9.1/output"
scenario_jobs <- data.frame(
  db       = c("ssp2_ref", "ssp2_ndc_slow", "ssp2_ndc_fast"),
  scenario = c("SSP2-Ref", "SSP2-NDC-slow", "SSP2-NDC-fast"),
  label    = c("Ref", "NDC_slow", "NDC_fast"),
  stringsAsFactors = FALSE
)
# With scenario_jobs, db_name only names the output folder:
# output_dir = {db_path}/{db_name}_output = .../gcam-v9.1/output/ssp2_ndc_output
db_name <- "ssp2_ndc"

# === Region & year range ======================================================
target_region  <- "South Korea"
start_year     <- 2005
final_year     <- 2050
version_number <- "9.1"

# === Step1 query scope ========================================================
scenarios         <- scenario_jobs$scenario
desired_variables <- "All"
desired_regions   <- "All"           # the workbook keeps South Korea afterwards
# Market-name patterns passed to generate_report(ignore = ...)
ignore_markets    <- "^bio-ceiling$"

# === K-TRACES =================================================================
# USD_2010 -> USD_2025 with the US GDP deflator (BEA A191RD3A086NBEA via FRED).
ktraces_deflator_file <- file.path(getwd(), "kaist/ktraces/data/FRED_A191RD3A086NBEA_20261008.csv")
# Industry extensions (Construction, Mining, service output): patch_project_data(),
# called by kaist/ktraces/step1_ktraces.R. Not for IAMC/KMIP submissions.
source(file.path(getwd(), "kaist/ktraces/functions.R"))
