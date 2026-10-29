################################################################################
# KMIP run settings: ssp2
# gcam-kaist9 (GCAM 9.1) SSP2-Ref / SSP2-NDC-fast / SSP2-NDC-slow, one BaseX DB
# per scenario, DBs in kaist/scenario/input/ssp2/ (ssp2_ref, ssp2_ndc_fast, ssp2_ndc_slow).
# Local test run of the five steps (kaist/scenario/RESULT.md).
# Used through the loader: KAIST_CONFIG=kaist/kmip/config/ssp2.R Rscript <step script>
#   or: kaist/kmip/run_pipeline.sh kaist/kmip/config/ssp2.R
# Derived paths, template paths and kaist/core/functions.R are set by kaist/core/config.R.
################################################################################

# === Run name (output prefix) =================================================
run_name <- "reports_ssp2"

# === GCAM databases ===========================================================
db_path <- file.path(getwd(), "kaist", "scenario", "input", "ssp2")
# Outputs: kaist/scenario/output/reports_ssp2 (overrides the {db_name}_output default)
output_dir <- file.path(getwd(), "kaist", "scenario", "output", run_name)
# One generate_report() call per row (see step1_jobs() in kaist/core/config.R);
# step1_parallel.R starts one worker per row.
scenario_jobs <- data.frame(
  db       = c("ssp2_ref", "ssp2_ndc_fast", "ssp2_ndc_slow"),
  scenario = c("SSP2-Ref", "SSP2-NDC-fast", "SSP2-NDC-slow"),
  label    = c("Ref", "NDC_fast", "NDC_slow"),
  stringsAsFactors = FALSE
)
db_name <- scenario_jobs$db[[1]]          # first DB (output_dir is set above)

# === Region & year range ======================================================
target_region  <- "South Korea"
start_year     <- 2005
final_year     <- 2050
version_number <- "9.1"

# === Step1 query scope ========================================================
scenarios         <- scenario_jobs$scenario
desired_variables <- "All"
desired_regions   <- "All"
# Policy markets dropped from the price rows: the core default
# (kaist_ignore_markets in kaist/core/functions.R) covers bio-ceiling and the
# other KAIST ceilings / caps.

# === Step2 options ============================================================
# Scenario whose 2020 values anchor the vehicle-capacity conversion ratio (b4).
ref_scenario  <- scenario_jobs$scenario[[1]]
verbose_debug <- FALSE
# KMIP2025 MT reference workbook (steel coal split + process factor for b3/b6)
# is not stored with the scenario inputs: built-in constants are used.

# === Step5 report: GHG pathway figure ========================================
plot_measures   <- "Net"
plot_start_year <- 2015
plot_subtitle   <- "SSP2 Ref / NDC-fast / NDC-slow"
pathway_targets <- NULL
pathway_caps    <- NULL
# No compare_a_file: step5 draws the figure only (no quarto comparison report).

# === Step4 check ==============================================================
check_tol_rel_a <- 1e-2   # raw query sums vs step1 (CO2 bio corrections need slack)
check_tol_rel_b <- 1e-6   # step1-vs-step2 pass-through rows
check_tol_rel_c <- 1e-6   # parent = sum(children)
check_tol_rel_d <- 1e-6   # recomputed template vs step3 output
check_strict      <- FALSE
check_checkpoints <- c("A", "B", "C", "D")
