################################################################################
# KAIST GCAM Report Configuration -- pj-test (local Windows test run)
#
# A copy of kaist/core/config.R adapted to test-run this repo on pjhan's
# Windows machine against the stock GCAM v8.2 release database.
# Source this at the top of each pj-test step file (from the repo root):
#   source(file.path(getwd(), "kaist/core/pj-test/config.R"))
#
# Differences from kaist/core/config.R:
#   * Windows paths to C:/Users/pjhan/Desktop/GCAM/gcam-v8.2-Windows-Release-Package
#   * version_number "8.2" (highest version this repo's mappings support;
#     the v9.1 DB used by Testrun.R needs upstream gcamreport, not this repo)
#   * scenarios = "Reference" (the only scenario in the release DB)
#   * apply_kaist_patch / apply_rgcam_patch switches (both off: the stock DB
#     has none of the KAIST policy markets, and rgcam 1.2.0 opens BaseX fine
#     on this machine without the "-i" workaround)
#   * all helper scripts are referenced under kaist/core/pj-test/
################################################################################

# === pj-test location =========================================================
# Folder holding this config and its siblings, relative to the repo root.
pjtest_dir <- "kaist/core/pj-test"

# === Run name (output prefix) =================================================
run_name <- "pjtest_v8.2"

# === GCAM database ============================================================
# Folder that contains the GCAM BaseX database folder.
db_path <- "C:/Users/pjhan/Desktop/GCAM/gcam-v8.2-Windows-Release-Package/output"
# Which database inside db_path to query.
db_name <- "database_basexdb"

# === Region & year range ======================================================
target_region <- "South Korea"   # Region used in the Korea-only blocks
start_year    <- 2005            # First year kept in step2 / step4
final_year    <- 2050            # Last year kept in step2 / step4
version_number <- "8.2"          # GCAM version (used for queries and rda lookups)

# === Step1 query scope ========================================================
scenarios         <- "Reference"
desired_variables <- "All"                        # "All" for everything
desired_regions   <- "All"                        # "All" or a character vector

# === pj-test switches =========================================================
# Re-apply the KAIST data overrides (patch_gcam_data) before load_all.
# FALSE for the stock release DB: kaist_overrides has no "v8.2" block and the
# DB has no bio-ceiling / Gen_III_Korea entries, so there is nothing to patch.
apply_kaist_patch <- FALSE
# Source rgcam_patch.R (BaseX 9.5+ "-i" workaround). Not needed on this
# machine: upstream rgcam already produced the gcam_v8.2_report_* files here.
# Flip to TRUE if you hit "Database does not exist or is invalid".
apply_rgcam_patch <- FALSE
# Build data/*_v8.2.rda from inst/extdata/saveDataFiles_*.R when missing.
# data/ is gitignored in this repo, so a fresh clone has no rda files.
build_data_if_missing <- TRUE

# === Step2 options ============================================================
ref_scenario <- "Reference"
verbose_debug <- FALSE
# KMIP2025 MT reference workbook. Not available locally -> built-in constants.
mt_reference_path <- file.path(db_path, "KMIP25_6Scenarios_output", "iron_report",
  "(붙임 2-1) KMIP2025 상향식 모형 분석 결과_장기감축경로_MT+GC+MS (참고용).xlsx")

# === Step6 options ============================================================
plot_measures   <- "Net"
plot_start_year <- 2015
plot_subtitle   <- "GCAM v8.2 release DB, Reference scenario (pj-test)"
pathway_targets <- NULL   # no statutory targets for the stock Reference run
pathway_caps    <- NULL

# === Step5 validation =========================================================
step5_tol_rel_a <- 1e-2
step5_tol_rel_b <- 1e-6
step5_tol_rel_c <- 1e-6
step5_tol_rel_d <- 1e-6
step5_strict <- FALSE
step5_checkpoints <- c("A", "B", "C", "D")

# === Derived paths (no need to edit these usually) ============================
# Outputs go to their own folder next to the database so they do not mix with
# the gcam_v8.2_report_* files that Testrun.R (upstream gcamreport) wrote.
output_dir <- file.path(db_path, paste0(run_name, "_output"))
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Coefficient files used by step2.
kaist_data_dir <- file.path(getwd(), "kaist/kmip/data")

# Display name for the report Model column.
model_name <- paste("GCAM", version_number)

# === Template & mapping (used by step3 / step4) ===============================
template_path <- file.path(output_dir, "KMIP2025_DB_final.xlsx")
mapping_path  <- file.path(output_dir, "kmip_gcam_mapping_template.xlsx")

cat("Config loaded (pj-test): run_name =", run_name,
    ", db =", file.path(db_path, db_name),
    ", version = v", version_number,
    ", output_dir =", output_dir, "\n")

# === Sanity checks ============================================================
if (!file.exists(file.path(getwd(), "DESCRIPTION"))) {
  stop("Run from the gcamreport-kaist repo root (DESCRIPTION not found in ", getwd(), ")")
}
if (!dir.exists(file.path(db_path, db_name))) {
  stop("GCAM database not found: ", file.path(db_path, db_name))
}

# === KAIST helper functions ===================================================
source(file.path(getwd(), pjtest_dir, "functions.R"))
