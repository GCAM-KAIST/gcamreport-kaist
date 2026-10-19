# [2026-10-04: Claude code] paths kaist/ -> kaist-pj/; new ignore_markets option; new step1_jobs() / step1_run_names() helpers for the scenario manifest.
################################################################################
# KAIST GCAM Report Configuration
#
# Shared settings for step1 ~ step5. Source this at the top of each step file:
#   source(file.path(getwd(), "kaist/core/config.R"))
#
# Most runs only need to change `run_name`, `db_name`, and the year range.
################################################################################

# Scenario-specific databases and names live in scenario/config.R.
scenario_config_path <- file.path(getwd(), "kaist", "scenario", "config.R")
if (file.exists(scenario_config_path)) {
  source(scenario_config_path)
}

# === Run name (output prefix) =================================================
# Change this to label a run. Every output file (xlsx, csv, .dat project file)
# will start with this prefix, and they are written under output_dir below.
# Example: "merge_test", "kaist_report", "kmip_v3"
run_name <- "reports_u0909"

# === GCAM database ============================================================
# Folder that contains the GCAM BaseX databases (DB25, DB26, ...).
db_path <- scenario_dir
# Which database inside db_path to query.
db_name <- scenario_jobs$db[[1]]

# === Region & year range ======================================================
target_region <- "South Korea"   # Region kept by step2 Part B / steps 3-6 ("All" leaves them an empty table)
start_year    <- 2005            # First year kept in step2 / step4
final_year    <- 2050            # Last year kept in step2 / step4
version_number <- sub("^v", "", scenario_gcam_version)

# === Step1 query scope ========================================================
# Which scenarios / variables / regions step1 asks generate_report() for.
scenarios         <- scenario_jobs$scenario
desired_variables <- "All"                        # "All" for everything
desired_regions   <- "All"                        # "All" or a character vector
# Market-name patterns passed to generate_report(ignore = ...).
# [2026-10-19] MUST be non-empty. Upstream R/functions.R::get_co2_price_fragmented_tmp()
# filters CO2 price markets with grepl(paste(ignore, collapse = "|"), market); with
# ignore = NULL the pattern is "" which matches every market, so ALL CO2 price
# markets are dropped and Price|Carbon / Revenue|Government come out as 0 (seen on
# the NZ scenario). gcamreport_patch.R used to guard this; it was removed to match
# main, so a real pattern is passed instead. The v9.1 kaist_overrides already map
# bio-ceiling to NoReported (fix 7), so the pattern itself changes nothing else.
ignore_markets <- if (exists("scenario_ignore")) scenario_ignore else "^bio-ceiling$"
if (length(ignore_markets) == 0 || !any(nzchar(ignore_markets))) {
  stop("config.R: ignore_markets must be a non-empty pattern (upstream drops every CO2 price market otherwise).")
}

# === Step2 options ============================================================
# Scenario whose 2020 values anchor the vehicle-capacity conversion ratio in
# module b4. NULL = use the first scenario found in the data.
ref_scenario <- scenario_jobs$scenario[[1]]
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
plot_subtitle <- "pa = 0.01, da = 3.667, 2050 cap = 10"
# Optional target points drawn on the Net panel of the GHG pathway figure.
# NULL = none. A data frame with columns Scenario, year, value (Mt CO2eq/yr).
pathway_targets <- NULL
# Optional cap values as written in the GCAM XML (target + bunker share).
# NULL = none. Same columns as pathway_targets.
pathway_caps <- NULL

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

# === Derived paths (no need to edit these usually) ============================
# Each database gets its own output folder (DB26 -> kmip/DB26_output) so that
# runs against different databases do not mix. .dat project files from step1
# also land here so they sit next to their .xlsx / .csv siblings.
output_dir <- scenario_output_dir
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Coefficient files used by step2.
kaist_data_dir <- file.path(getwd(), "kaist/kmip/data")

# Display name for the report Model column.
model_name <- paste("GCAM", version_number)

# === Template & mapping (used by step3 / step4) ===============================
template_path <- file.path(output_dir, "KMIP2025_DB_final.xlsx")
mapping_path  <- file.path(output_dir, "kmip_gcam_mapping_template.xlsx")

cat("Config loaded: run_name =", run_name,
    ", db =", db_name,
    ", output_dir =", output_dir, "\n")

# === KAIST helper functions ===================================================
# Custom functions (available_variables_with_units, add_korea_cf, ...) kept in
# kaist/ so the package source under R/ stays identical to upstream.
source(file.path(getwd(), "kaist/core/functions.R"))

# === Step1 job list ===========================================================
# One row per generate_report() call. With a scenario manifest
# (kaist/scenario/config.R -> scenario_jobs) every job has its own BaseX
# database; otherwise the classic single-database run with all `scenarios`.
step1_jobs <- function() {
  if (exists("scenario_jobs")) {
    return(data.frame(db = scenario_jobs$db, scenario = I(as.list(scenario_jobs$scenario)),
                      label = scenario_jobs$label, stringsAsFactors = FALSE))
  }
  data.frame(db = db_name, scenario = I(list(scenarios)), label = run_name,
             stringsAsFactors = FALSE)
}
# Per-run output names used by the step1 worker/merge tools:
# {run_name}_{label} (manifest) or {run_name}_{scenario} (single database).
step1_run_names <- function() {
  if (exists("scenario_jobs")) return(paste0(run_name, "_", scenario_jobs$label))
  paste0(run_name, "_", scenarios)
}
