################################################################################
# KMIP run settings: kaist9_hlm
# gcam-kaist9 (GCAM 9.1) high/medium/low nuclear x ref/nz runs from Ahmed (2026-09-23 to 10-07).
# GCAM wrote one DB per run (kmip/KAIST9_HLM/{high_ref,...}); they were merged into
# kmip/KMIP26_HLM with kaist/core/tools/merge_basex_dbs.R.
# Used through the loader: KAIST_CONFIG=kaist/kmip/config/kaist9_hlm.R Rscript <step script>
# Derived paths, template paths and kaist/core/functions.R are set by kaist/core/config.R.
################################################################################

# === Run name (output prefix) =================================================
# Change this to label a run. Every output file (xlsx, csv, .dat project file)
# will start with this prefix, and they are written under output_dir ({db_path}/{db_name}_output).
# Example: "merge_test", "kaist_report", "kmip_v3"
run_name <- "kaist9_hlm"

# === GCAM database ============================================================
# Folder that contains the GCAM BaseX databases (DB25, DB26, ...).
db_path <- "/home/jiheun/reporting/kmip"
# Which database inside db_path to query.
db_name <- "KMIP26_HLM"
# Outputs stay in the folder of the first reports of these runs.
output_dir <- file.path(db_path, "KAIST9_HLM_output")

# === Region & year range ======================================================
target_region <- "South Korea"   # Region used in the Korea-only blocks
start_year    <- 2005            # First year kept in step2 / step4
final_year    <- 2050            # Last year kept in step2 / step4
version_number <- "9.1"          # GCAM version (used for queries and rda lookups)

# === Step1 query scope ========================================================
# Which scenarios / variables / regions step1 asks generate_report() for.
scenarios         <- c("KAIST_9_ref_u0923pv", "KAIST_9_NZ_u0923pv", "KAIST_9_ref_u0930med", "KAIST_9_NZ_u0930med",
                       "KAIST_9_ref_u1007low", "KAIST_9_NZ_u1007low")   # names inside the DB
# Short names used from the merged step1 outputs on (step1_merge.R).
scenario_labels   <- c(KAIST_9_ref_u0923pv = "high_ref", KAIST_9_NZ_u0923pv = "high_nz",
                       KAIST_9_ref_u0930med = "medium_ref", KAIST_9_NZ_u0930med = "medium_nz",
                       KAIST_9_ref_u1007low = "low_ref", KAIST_9_NZ_u1007low = "low_nz")
desired_variables <- "All"                        # "All" for everything
desired_regions   <- "South Korea"                # "All" or a character vector
# KAIST policy markets that are not reported (generate_report(ignore = ...)):
# ceilings/floors, the Korea CO2/GHG caps and the rest-of-world caps. Without
# this list their shadow prices leak into the biomass and solids price rows.
ignore_markets    <- c("-ceiling", "_ceiling", "bio-ceiling", "coal-ceiling", "irnstl-ceiling",
                       "irnstl_ceiling_EAF", "dac-ceiling", "Generation-Ceiling", "Generation-Floor",
                       "CO2_Kor", "GHG_Kor", "rowbio-ceiling", "rowCO2")

# === Step2 options ============================================================
# Scenario whose 2020 values anchor the vehicle-capacity conversion ratio in
# module b4. NULL = use the first scenario found in the data.
ref_scenario <- "medium_ref"
# TRUE prints the diagnostic tables from modules a4 / b3 / b5 (CF check,
# steel coal ratios, biomass share). FALSE keeps the step2 console output short.
verbose_debug <- FALSE
# KMIP2025 MT reference workbook (steel coal split + process factor for b3/b6).
# If missing, built-in constants are used.
mt_reference_path <- file.path(db_path, "KMIP25_6Scenarios_output", "iron_report",
  "(붙임 2-1) KMIP2025 상향식 모형 분석 결과_장기감축경로_MT+GC+MS (참고용).xlsx")

# === Step6 options ============================================================
# Panels to draw: c("Gross", "Net") or just "Net".
plot_measures <- "Net"
# First year on the x axis of the figure.
plot_start_year <- 2015
# Text under the title (NULL = none). Used here for the cap settings.
plot_subtitle <- "GCAM-KAIST 9.1 (high / low / medium x ref / nz)"
# Optional target points drawn on the Net panel of the GHG pathway figure.
# NULL = none. A data frame with columns Scenario, year, value (Mt CO2eq/yr).
pathway_targets <- NULL
# Optional cap values as written in the GCAM XML. NULL = none.
pathway_caps <- NULL

# === Step7 comparison =========================================================
# Reference run: the KMIP2025 submission workbook (sheet "data", Model column)
# or a step4 csv (variables_after_unit_conversion.csv) of an earlier run.
compare_a_file  <- file.path(db_path, "KMIP25_6Scenarios_output",
  "(붙임 2-1) KMIP2025 상향식 모형 분석 결과_장기감축경로_MT+GC+MS (참고용).xlsx")
compare_a_model <- "GC"
compare_a_label <- "KMIP25 GC"
compare_a_scenarios <- c("S0.7_ESM", "S0.8_ESM", "S0.9", "S1", "S1.1")
compare_b_label <- "K9"
compare_b_scenarios <- unname(scenario_labels)
compare_pair    <- c(a = "S1", b = "low_nz")
compare_ref_step2_csv <- file.path(db_path, "KMIP25_6Scenarios_output", "kmip26_all8_korea.csv")

# === Step5 validation =========================================================
# Relative tolerances per checkpoint (rel_diff = |a-b| / max(|a|,|b|,1e-12)).
step5_tol_rel_a <- 1e-2   # raw query sums vs step1 (CO2 bio corrections need slack)
step5_tol_rel_b <- 1e-6   # step1-vs-step2 pass-through rows
step5_tol_rel_c <- 1e-6   # parent = sum(children)
step5_tol_rel_d <- 1e-6   # recomputed template vs step4 output
# TRUE (or --strict on the command line) turns any FAIL into an error exit.
step5_strict <- FALSE
# Checkpoints to run by default; --checkpoints=A,C overrides.
step5_checkpoints <- c("A", "B", "C", "D")
