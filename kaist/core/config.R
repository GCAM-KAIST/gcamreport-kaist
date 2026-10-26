################################################################################
# KAIST GCAM Report Configuration (loader)
#
# Every step sources this file:
#   source(file.path(getwd(), "kaist/core/config.R"))
#
# It holds no run settings. It reads the run settings file named by the
# KAIST_CONFIG environment variable (path from the repo root), then sets the
# derived paths and loads kaist/core/functions.R. Each project keeps its own
# settings files, e.g. kaist/kmip/config/kaist9_hlm.R:
#   KAIST_CONFIG=kaist/kmip/config/kaist9_hlm.R Rscript kaist/kmip/step3_template.R
#   Sys.setenv(KAIST_CONFIG = "kaist/kmip/config/kaist9_hlm.R")   # in RStudio
################################################################################

kaist_config <- Sys.getenv("KAIST_CONFIG")
if (kaist_config == "") {
  found <- list.files(file.path(getwd(), "kaist"), pattern = "\\.R$", recursive = TRUE)
  found <- grep("(^|/)config/", found, value = TRUE)
  stop("KAIST_CONFIG is not set. Choose a run settings file, e.g.\n",
       "  Sys.setenv(KAIST_CONFIG = \"kaist/kmip/config/kaist9_hlm.R\")\n",
       "Available:\n", paste0("  kaist/", found, collapse = "\n"), call. = FALSE)
}
if (!file.exists(kaist_config)) kaist_config <- file.path(getwd(), kaist_config)
if (!file.exists(kaist_config)) stop("KAIST_CONFIG file not found: ", Sys.getenv("KAIST_CONFIG"), call. = FALSE)
source(kaist_config)

# === Derived paths (no need to edit these usually) ============================
# Each database gets its own output folder (DB26 -> kmip/DB26_output) so that
# runs against different databases do not mix. .dat project files from step1
# also land here so they sit next to their .xlsx / .csv siblings.
# A settings file may set output_dir itself (e.g. kaist/scenario/output/{run_name}).
if (!exists("output_dir"))
  output_dir <- file.path(db_path, paste0(db_name, "_output"))
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Coefficient files used by step2.
kaist_data_dir <- file.path(getwd(), "kaist/kmip/data")

# Display name for the report Model column.
model_name <- paste("GCAM", version_number)

# === Template & mapping (used by tools/make_mapping.R and step3) ===============================
# A settings file may set its own; otherwise the KMIP2025 files in the repo.
if (!exists("template_path"))
  template_path <- file.path(getwd(), "kaist/kmip/template/KMIP2025_DB_final.xlsx")
if (!exists("mapping_path"))
  mapping_path <- file.path(getwd(), "kaist/kmip/template/kmip_gcam_mapping_template.xlsx")
# Submitted KMIP layout (sheet "Template(제출용)", values removed) for the step3 workbook
if (!exists("submission_template_path"))
  submission_template_path <- file.path(getwd(), "kaist/kmip/template/KMIP2025_DB_template_submission.xlsx")

cat("Config loaded:", Sys.getenv("KAIST_CONFIG"), "| run_name =", run_name,
    "| db =", db_name, "| output_dir =", output_dir, "\n")

# === KAIST helper functions ===================================================
# Custom functions (available_variables_with_units, add_korea_cf, ...) kept in
# kaist/ so the package source under R/ stays identical to upstream.
source(file.path(getwd(), "kaist/core/functions.R"))

# === Step1 job list ===========================================================
# One row per generate_report() call. If the settings file defines
# scenario_jobs (data frame with db, scenario, label), every job has its own
# BaseX database inside db_path; otherwise one job: db_name with all `scenarios`.
step1_jobs <- function() {
  if (exists("scenario_jobs")) {
    return(data.frame(db = scenario_jobs$db, scenario = I(as.list(scenario_jobs$scenario)),
                      label = scenario_jobs$label, stringsAsFactors = FALSE))
  }
  data.frame(db = db_name, scenario = I(list(scenarios)), label = run_name,
             stringsAsFactors = FALSE)
}
# Per-run output names used by the step1 worker/merge tools:
# {run_name}_{label} (scenario_jobs) or {run_name}_{scenario} (single database).
step1_run_names <- function() {
  if (exists("scenario_jobs")) return(paste0(run_name, "_", scenario_jobs$label))
  paste0(run_name, "_", scenarios)
}
