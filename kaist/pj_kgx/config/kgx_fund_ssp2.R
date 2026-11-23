################################################################################
# Run settings: kgx_fund_ssp2 (pj_kgx; K-GX fund runs of pj_gcam_runs, SSP2)
# K-ETS price that the K-GX plan needs, charged in South Korea by K-ETS class
# (power / other paying industry / carbon-leakage list) through linked markets.
# Inputs: pj_gcam_runs/carbon_pricing/input/configuration/kgx_fund_scenarios.
# Used through the loader, from the repo root:
#   step1:  KAIST_CONFIG=kaist/pj_kgx/config/kgx_fund_ssp2.R Rscript kaist/core/step1_generate_report.R
#   rows:   KAIST_CONFIG=kaist/pj_kgx/config/kgx_fund_ssp2.R Rscript kaist/pj_kgx/build_kgx_report.R
################################################################################

# === Run name (output prefix) =================================================
run_name <- "kgx_fund_ssp2"

# === GCAM database ============================================================
# The K-GX database sits in pj_gcam_runs, next to this repository's parent folder
# (iam_models/GCAM/pj_gcam_runs). Outputs: {db_path}/{db_name}_output (outside the repo).
db_path <- normalizePath(file.path(getwd(), "..", "..", "..", "pj_gcam_runs", "carbon_pricing", "output"),
                         winslash = "/", mustWork = TRUE)
db_name <- "kgx_fund_db"

# === Region & year range ======================================================
target_region  <- "South Korea"
start_year     <- 2005
final_year     <- 2100
version_number <- "9.1"

# === Step1 query scope ========================================================
scenarios         <- c("SSP2_KGX_Central", "SSP2_KGX_Leak05")
desired_variables <- "All"
desired_regions   <- "All"

# === pj_kgx ===================================================================
# Project functions (K-ETS market names) and the extra query that step1 adds to the project.
source(file.path(getwd(), "kaist/pj_kgx/functions.R"))
project_queries <- file.path(getwd(), "kaist/pj_kgx/data/kgx_queries.xml")
# Policy markets dropped from the price rows: the core list plus the K-ETS markets. They are
# priced by build_kgx_report.R; gcamreport's market mapping does not know them.
ignore_markets <- c(kaist_ignore_markets, kgx_ignore_markets)

# build_kgx_report.R
kgx_region       <- target_region
kgx_face_market  <- "CO2_KETS"                       # <region><face market>  = allowance price
kgx_classes_file <- file.path(getwd(), "kaist/pj_kgx/data/kgx_classes.csv")
# FALSE: the gcamreport rows stay exactly as step1 wrote them (Price|Carbon and Revenue|Government
# of the region stay 0) and the K-ETS rows are added. TRUE: the region's Price|Carbon becomes the
# allowance price and Revenue|Government the K-ETS revenue.
kgx_fill_headline <- FALSE
