################################################################################
# Run settings: ssp2 (gcam-kaist9 SSP2-Ref / SSP2-NDC-fast / SSP2-NDC-slow,
# one BaseX DB per scenario, DBs in kaist/scenario/input/ssp2/).
# Used through the loader: KAIST_CONFIG=kaist/kmip/config/ssp2.R Rscript <step script>
################################################################################

# === Run name (output prefix) =================================================
run_name <- "reports_ssp2"

# === GCAM databases ===========================================================
db_path <- file.path(getwd(), "kaist", "scenario", "input", "ssp2")
# Outputs: kaist/scenario/output/reports_ssp2 (overrides the {db_name}_output default)
output_dir <- file.path(getwd(), "kaist", "scenario", "output", run_name)
# One generate_report() call per row (see step1_jobs() in kaist/core/config.R).
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
# Market-name patterns passed to generate_report(ignore = ...)
ignore_markets    <- "^bio-ceiling$"

# === Step2 options ============================================================
ref_scenario <- scenario_jobs$scenario[[1]]
verbose_debug <- FALSE
mt_reference_path <- file.path(db_path, "KMIP25_6Scenarios_output", "iron_report",
  "(붙임 2-1) KMIP2025 상향식 모형 분석 결과_장기감축경로_MT+GC+MS (참고용).xlsx")

# === Step6 options ============================================================
plot_measures   <- "Net"
plot_start_year <- 2015
plot_subtitle   <- "SSP2 Ref / NDC-fast / NDC-slow"
pathway_targets <- NULL
pathway_caps    <- NULL

# === Step5 validation =========================================================
step5_tol_rel_a <- 1e-2
step5_tol_rel_b <- 1e-6
step5_tol_rel_c <- 1e-6
step5_tol_rel_d <- 1e-6
step5_strict <- FALSE
step5_checkpoints <- c("A", "B", "C", "D")
