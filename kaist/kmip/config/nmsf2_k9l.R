################################################################################
# KMIP run settings: nmsf2_k9l
# NMSF2 runs on GCAM-KAIST9 (gcam-kaist9 PR #6, u1007low base): reference,
# less ambition, more ambition. GCAM wrote one DB per run (now in
# kmip/NMSF2_K9L_runs/, links to the gcam-kaist9-nmsf2 output folder); they are
# merged into kmip/NMSF2_K9L with kaist/core/tools/merge_basex_dbs.R.
# Run: kaist/kmip/run_pipeline.sh kaist/kmip/config/nmsf2_k9l.R (steps 1, 2, 5, 6)
# NMSF2-only mapping rows (kaist/kmip/functions.R) and queries (kaist/kmip/data/)
# are wired in at the end of this file.
################################################################################

run_name <- "nmsf2_k9l"
db_path <- "/home/jiheun/reporting/kmip"
db_name <- "NMSF2_K9L"
target_region  <- "South Korea"
start_year     <- 2005
final_year     <- 2050
version_number <- "9.1"
scenarios         <- c("NMSF2_reference_k9l", "NMSF2_less_ambition_k9l", "NMSF2_more_ambition_k9l")   # names inside the DB
# Short names used from the merged step1 outputs on (step1_merge.R).
scenario_labels   <- c(NMSF2_reference_k9l = "ref_k9l", NMSF2_less_ambition_k9l = "less_k9l",
                       NMSF2_more_ambition_k9l = "more_k9l")
# KAIST policy markets that are not reported (generate_report(ignore = ...)); the
# NMSF2 gases (GHG_Kor, bunker and LULUCF adjustments) are mapped to NoReported instead.
ignore_markets    <- c("-ceiling", "_ceiling", "bio-ceiling", "coal-ceiling", "irnstl-ceiling",
                       "irnstl_ceiling_EAF", "dac-ceiling", "Generation-Ceiling", "Generation-Floor",
                       "CO2_Kor", "GHG_Kor", "rowbio-ceiling", "rowCO2")
# No KMIP template for NMSF2: run_pipeline.sh runs only these steps (no step3).
run_steps         <- c(1, 2, 4, 5)
desired_variables <- "All"
desired_regions   <- c("South Korea", "Japan")   # Korea alone stops: no purpose-grown biomass in Korea (land frozen); Japan has it, Korea values unchanged
ref_scenario <- "ref_k9l"
verbose_debug <- FALSE
mt_reference_path <- file.path(db_path, "KMIP25_6Scenarios_output", "iron_report",
  "(붙임 2-1) KMIP2025 상향식 모형 분석 결과_장기감축경로_MT+GC+MS (참고용).xlsx")
plot_measures   <- "Net"
plot_start_year <- 2015
plot_subtitle   <- "GCAM-KAIST 9.1, NMSF2 (u1007low): reference, less and more ambition"
# statutory national net targets (MtCO2eq); international mitigation is not in the report
pathway_targets <- data.frame(
  Scenario = rep(c("less_k9l", "more_k9l"), each = 5),
  year     = rep(c(2030, 2035, 2040, 2045, 2050), 2),
  value    = c(470.3, 348.9, 230.1, 118.8, 0,
               470.3, 289.5, 148.5, 74.2, 0))
pathway_caps <- NULL
check_tol_rel_a <- 1e-2
check_tol_rel_b <- 1e-6
check_tol_rel_c <- 1e-6
check_tol_rel_d <- 1e-6
check_strict <- FALSE
check_checkpoints <- c("A", "B", "C")   # no step3 (KMIP template) for NMSF2

# === NMSF2-only data =========================================================
# Mapping rows for the NMSF2 gases (step1 project hook) and the LULUCF inventory
# adjustment query that step2 module b9 reads.
source(file.path(getwd(), "kaist/kmip/functions.R"))
project_queries <- file.path(getwd(), "kaist/kmip/data/nmsf2_queries.xml")
