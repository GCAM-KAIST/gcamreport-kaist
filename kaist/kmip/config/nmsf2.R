################################################################################
# KMIP run settings: nmsf2
# NMSF 2.0 runs (GCAM-KAIST 7, NMSF2 database).
# Used through the loader: KAIST_CONFIG=kaist/kmip/config/nmsf2.R Rscript <step script>
# Derived paths, template paths and kaist/core/functions.R are set by kaist/core/config.R.
################################################################################

# === Run name (output prefix) =================================================
# Change this to label a run. Every output file (xlsx, csv, .dat project file)
# will start with this prefix, and they are written under output_dir ({db_path}/{db_name}_output).
# Example: "merge_test", "kaist_report", "kmip_v3"
run_name <- "nmsf2"

# === GCAM database ============================================================
# Folder that contains the GCAM BaseX databases (DB25, DB26, ...).
db_path <- "/home/jiheun/reporting/kmip"
# Which database inside db_path to query.
db_name <- "NMSF2"

# === Region & year range ======================================================
target_region <- "South Korea"   # Region used in the Korea-only blocks
start_year    <- 2005            # First year kept in step2 / step3
final_year    <- 2050            # Last year kept in step2 / step3
version_number <- "7.0"          # GCAM version (used for queries and rda lookups)

# === Step1 query scope ========================================================
# Which scenarios / variables / regions step1 asks generate_report() for.
scenarios         <- c("NMSF2_concave", "NMSF2_convex")
desired_variables <- "All"                        # "All" for everything
desired_regions   <- "All"                        # "All" or a character vector
# KAIST policy markets that are not reported (generate_report(ignore = ...)):
# ceilings/floors, the Korea CO2/GHG caps and the rest-of-world caps. Without
# this list their shadow prices leak into the biomass and solids price rows.
ignore_markets    <- c("-ceiling", "_ceiling", "bio-ceiling", "coal-ceiling", "irnstl-ceiling",
                       "irnstl_ceiling_EAF", "dac-ceiling", "Generation-Ceiling", "Generation-Floor",
                       "CO2_Kor", "GHG_Kor", "rowbio-ceiling", "rowCO2")

# === Step2 options ============================================================
# Scenario whose 2020 values anchor the vehicle-capacity conversion ratio in
# module b4. NULL = use the first scenario found in the data.
ref_scenario <- "NMSF2_concave"   # no "ref" in the NMSF2 DB; 2020 is the same in all scenarios
# TRUE prints the diagnostic tables from modules a4 / b3 / b5 (CF check,
# steel coal ratios, biomass share). FALSE keeps the step2 console output short.
verbose_debug <- FALSE
# KMIP2025 MT reference workbook (steel coal split + process factor for b3/b6).
# If missing, built-in constants are used.
mt_reference_path <- file.path(db_path, "KMIP25_6Scenarios_output", "iron_report",
  "(붙임 2-1) KMIP2025 상향식 모형 분석 결과_장기감축경로_MT+GC+MS (참고용).xlsx")

# === Step5 report: GHG pathway figure ============================================================
# Panels to draw: c("Gross", "Net") or just "Net".
plot_measures <- "Net"
# First year on the x axis of the figure.
plot_start_year <- 2015
# Text under the title (NULL = none). Used here for the cap settings.
plot_subtitle <- "pa = 0.01, da = 3.667, 2050 cap = 10"
# Optional target points drawn on the Net panel of the GHG pathway figure.
# NULL = none. A data frame with columns Scenario, year, value (Mt CO2eq/yr).
pathway_targets <- data.frame(
  Scenario = rep(c("NMSF2_concave", "NMSF2_convex"), each = 5),
  year     = rep(c(2030, 2035, 2040, 2045, 2050), 2),
  value    = c(470.3, 348.9, 230.1, 118.8, 0,     # statutory lower bound (linear)
               470.3, 289.5, 148.5, 74.2, 0))     # statutory upper bound (early cuts)
# Optional cap values as written in the GCAM XML (target + bunker share).
# NULL = none. Same columns as pathway_targets.
pathway_caps <- data.frame(
  Scenario = rep(c("NMSF2_concave", "NMSF2_convex"), each = 5),
  year     = rep(c(2030, 2035, 2040, 2045, 2050), 2),
  value    = c(496.06, 371.23, 248.75, 131.12, 10.09,
               496.06, 308.33, 161.95, 77.44, 10.34))

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
