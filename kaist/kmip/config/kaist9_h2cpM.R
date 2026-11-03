################################################################################
# KMIP run settings: kaist9_h2cpM
# KMIP26 hydrogen price runs with the carbon price fixed to the cpM path (탄소가격 시나리오 M,
# thousand KRW/tCO2 2025 real: 9.5, 100, 185, 341, 630, 1163 for 2025-2050), run 2026-11-03.
# Base: configs KAIST_9_NZ_u1028oilM (oil price M with 2021 adjustment +0.11, nuclear plan11d
# low + SMR 2030 plan, elec_water_pvcf) on the standard gcam-9.1 xml, with
#   - CO2_Kor cap replaced by a fixed tax on the same policy (kor_CO2_tax_cpM.xml; the CO2 link
#     file is unchanged, so CO2 pays 1x, CO2_LUC 0.5x the CO2_Kor price)
#   - H2_truck_trade.xml freight input in GCAM 9.1 units (1.664 billion tkm per EJ, price
#     conversion 1, as the domestic H2 liquid truck; the shared file has the GCAM 7 values)
#   - h2L/M/H: "regional price adjustment" on South Korea H2 industrial to the Table II-3 H2 prices
# Files: /home/jiwon/kmip26/hydrogen/h2; configs gcam-v9.1/exe_h2price/config_cpM_oilM*.xml.
# Used through the loader: KAIST_CONFIG=kaist/kmip/config/kaist9_h2cpM.R Rscript <step script>
# Derived paths, template paths and kaist/core/functions.R are set by kaist/core/config.R.
################################################################################

# === Run name (output prefix) =================================================
# Change this to label a run. Every output file (xlsx, csv, .dat project file)
# will start with this prefix, and they are written under output_dir ({db_path}/{db_name}_output).
run_name <- "kaist9_h2cpM"

# === GCAM database ============================================================
# Folder that contains the GCAM BaseX databases.
db_path <- "/home/jiwon/gcam/gcam-v9.1/output"
# Which database inside db_path to query.
db_name <- "h2price2"

# === Region & year range ======================================================
target_region <- "South Korea"   # Region used in the Korea-only blocks
start_year    <- 2005            # First year kept in step2 / step3
final_year    <- 2050            # Last year kept in step2 / step3
version_number <- "9.1"          # GCAM version (used for queries and rda lookups)

# === Step1 query scope ========================================================
# Which scenarios / variables / regions step1 asks generate_report() for.
scenarios         <- c("261103_cpM_oilM", "261103_cpM_oilM_h2L_ind",
                       "261103_cpM_oilM_h2M_ind", "261103_cpM_oilM_h2H_ind")   # names inside the DB
# Short names used from the merged step1 outputs on (step1_merge.R).
scenario_labels   <- c("261103_cpM_oilM" = "cpM_ctl", "261103_cpM_oilM_h2L_ind" = "cpM_h2L",
                       "261103_cpM_oilM_h2M_ind" = "cpM_h2M", "261103_cpM_oilM_h2H_ind" = "cpM_h2H")
desired_variables <- "All"                        # "All" for everything
desired_regions   <- "South Korea"                # "All" or a character vector
# Policy markets dropped from the price rows: the core default (kaist_ignore_markets
# in kaist/core/functions.R) covers the KAIST ceilings and caps.

# === Step2 options ============================================================
# Scenario whose 2020 values anchor the vehicle-capacity conversion ratio in
# module b4. NULL = use the first scenario found in the data.
ref_scenario <- "cpM_ctl"
# TRUE prints the diagnostic tables from modules a4 / b3 / b5 (CF check,
# steel coal ratios, biomass share). FALSE keeps the step2 console output short.
verbose_debug <- FALSE
# bunker_mode: not set (default "split"); the standard gcam-9.1 xml pools Korea domestic and
# international aviation / shipping, as in kaist9_low26.
# KMIP2025 MT reference workbook (steel coal split + process factor for b3/b6): the copy under
# /home/jiheun/reporting/kmip is not readable from this account, so the built-in constants are used.
mt_reference_path <- ""

# === Step5 report: GHG pathway figure ============================================================
# Panels to draw: c("Gross", "Net") or just "Net".
plot_measures <- "Net"
# First year on the x axis of the figure.
plot_start_year <- 2015
# Text under the title (NULL = none).
plot_subtitle <- "GCAM-KAIST 9.1, u1028oilM, carbon price cpM (no CO2 cap), H2 price L/M/H, run 2026-11-03"
# Optional target points drawn on the Net panel of the GHG pathway figure.
pathway_targets <- NULL
# Optional cap values as written in the GCAM XML. NULL = none (these runs have no cap).
pathway_caps <- NULL
# No comparison with a reference run (compare_a_file): the KMIP2025 workbook is under
# /home/jiheun/reporting/kmip, not readable from this account. step5 skips the comparison report.

# === Step4 check =========================================================
# Relative tolerances per checkpoint (rel_diff = |a-b| / max(|a|,|b|,1e-12)).
check_tol_rel_a <- 1e-2   # raw query sums vs step1 (CO2 bio corrections need slack)
check_tol_rel_b <- 1e-6   # step1-vs-step2 pass-through rows
check_tol_rel_c <- 1e-6   # parent = sum(children)
check_tol_rel_d <- 1e-6   # recomputed template vs step3 output
# TRUE (or --strict on the command line) turns any FAIL into an error exit.
check_strict <- FALSE
# Checkpoints to run by default; --checkpoints=A,C overrides.
check_checkpoints <- c("A", "B", "C", "D")
