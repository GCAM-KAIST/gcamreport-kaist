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
# Policy markets dropped from the price rows: the core default (kaist_ignore_markets
# in kaist/core/functions.R) covers the KAIST ceilings and caps. A run with other
# cap markets adds them: ignore_markets <- c(kaist_ignore_markets, "...").
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
# Text under the figure (NULL = none): what the cap covers and the pa / da settings.
plot_caption <- paste0(
  "Cap on all 23 GHGs in one South Korea market (MtCO2eq, GWP AR5).\n",
  "pa = CO2_LUC price-adjust (share of the carbon price that land receives)\n",
  "da = CO2_LUC demand-adjust (3.667 = land-use CO2 counted in the cap); cap = 2050 constraint, MtCO2eq")
# statutory national net targets (MtCO2eq); international mitigation is not in the report
pathway_targets <- data.frame(
  Scenario = rep(c("less_k9l", "more_k9l"), each = 5),
  year     = rep(c(2030, 2035, 2040, 2045, 2050), 2),
  value    = c(470.3, 348.9, 230.1, 118.8, 0,
               470.3, 289.5, 148.5, 74.2, 0))
pathway_caps <- NULL
# b1: "split" re-splits aviation/shipping by the GIR domestic ratios (databases without the
# L154 split, like these); "intl" uses the trn_*_intl rows as they are (databases with it).
bunker_mode <- "split"
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
