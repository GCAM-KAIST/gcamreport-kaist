################################################################################
# KMIP run settings: u0909
# gcam-kaist9 (GCAM 9.1) KAIST_9_Ref_u0909 / KAIST_9_NZ_u0909, one BaseX DB per
# scenario, DBs and scenario XMLs in kaist/scenario/input/u0909/ (u0909r, u0909n).
# Local test run of the five steps (kaist/scenario/RESULT.md).
# Used through the loader: KAIST_CONFIG=kaist/kmip/config/u0909.R Rscript <step script>
#   or: kaist/kmip/run_pipeline.sh kaist/kmip/config/u0909.R
# Derived paths, template paths and kaist/core/functions.R are set by kaist/core/config.R.
################################################################################

# === Run name (output prefix) =================================================
run_name <- "reports_u0909"

# === GCAM databases ===========================================================
db_path <- file.path(getwd(), "kaist", "scenario", "input", "u0909")
# Outputs: kaist/scenario/output/reports_u0909 (overrides the {db_name}_output default)
output_dir <- file.path(getwd(), "kaist", "scenario", "output", run_name)
# One generate_report() call per row (see step1_jobs() in kaist/core/config.R);
# step1_parallel.R starts one worker per row.
scenario_jobs <- data.frame(
  db       = c("u0909r", "u0909n"),
  scenario = c("KAIST_9_ref_u0909", "KAIST_9_NZ_u0909"),
  label    = c("Ref_u0909", "NZ_u0909"),
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
plot_subtitle   <- "pa = 0.01, da = 3.667, 2050 cap = 10"
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
