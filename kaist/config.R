################################################################################
# KAIST GCAM Report Configuration
#
# Shared settings for step1 ~ step5. Source this at the top of each step file:
#   source(file.path(getwd(), "kaist/config.R"))
#
# Most runs only need to change `run_name`, `db_name`, and the year range.
################################################################################

# === Run name (output prefix) =================================================
# Change this to label a run. Every output file (xlsx, csv, .dat project file)
# will start with this prefix, and they are written under output_dir below.
# Example: "merge_test", "kaist_report", "kmip_v3"
run_name <- "merge_test"

# === GCAM database ============================================================
# Folder that contains the GCAM BaseX databases (DB25, DB26, ...).
db_path <- "C:/GCAM/gcamreport/kmip"
# Which database inside db_path to query.
db_name <- "DB26"

# === Region & year range ======================================================
target_region <- "South Korea"   # Region used in the Korea-only blocks
start_year    <- 2005            # First year kept in step2 / step4
final_year    <- 2035            # Last year kept in step2 / step4
version_number <- "7.0"          # GCAM version (used for queries and rda lookups)

# === Derived paths (no need to edit these usually) ============================
# Each database gets its own output folder (DB26 -> kmip/DB26_output) so that
# runs against different databases do not mix. .dat project files from step1
# also land here so they sit next to their .xlsx / .csv siblings.
output_dir <- file.path(db_path, paste0(db_name, "_output"))
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Coefficient files used by step2.
kaist_data_dir <- file.path(getwd(), "kaist/data")

# Display name for the report Model column.
model_name <- paste("GCAM", version_number)

# === Template & mapping (used by step3 / step4) ===============================
template_path <- file.path(output_dir, "KMIP2025_DB_final.xlsx")
mapping_path  <- file.path(output_dir, "kmip_gcam_mapping_template.xlsx")

cat("Config loaded: run_name =", run_name,
    ", db =", db_name,
    ", output_dir =", output_dir, "\n")
