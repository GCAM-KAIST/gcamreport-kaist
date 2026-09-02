################################################################################
# Step 5: Pipeline-wide validation
#
# Verifies that reported totals match raw GCAM DB sums at every stage:
#   A: raw query sums (.dat) vs step1 report + unmapped-name detection
#   B: step1 vs step2 (only documented module adjustments may differ)
#   C: parent variable = sum of children (catches double counting)
#   D: step2 korea csv -> independently recomputed KMIP template vs step4
#
# Standalone, runnable after any stage; missing inputs are skipped.
# Usage: Rscript kaist/step5_validate.R [--strict] [--checkpoints=A,C]
# Output: step5_summary.csv, step5_mismatches.csv, step5_unmapped.csv
# Tolerances / defaults: kaist/config.R "Step5 validation" section.
################################################################################

########## Load Configuration ##########
source(file.path(getwd(), "kaist/config.R"))
########################################

########## Libraries ##########
suppressMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(readxl)
  library(stringr)
  library(rlang)
})
################################

########## Load helpers ##########
source(file.path(getwd(), "kaist/modules/00_utils.R"))
source(file.path(getwd(), "kaist/unit_table.R"))
for (f in list.files(file.path(getwd(), "kaist/modules/validate"),
                     pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
##################################

########## CLI arguments ##########
args <- commandArgs(trailingOnly = TRUE)
strict <- step5_strict || any(args == "--strict")
checkpoints <- step5_checkpoints
cp_arg <- grep("^--checkpoints=", args, value = TRUE)
if (length(cp_arg) > 0) {
  checkpoints <- toupper(trimws(strsplit(sub("^--checkpoints=", "", cp_arg[1]), ",")[[1]]))
}
###################################

########## Input discovery ##########
paths <- list(
  step1_xlsx = file.path(output_dir, paste0(run_name, ".xlsx")),
  step2_csv  = file.path(output_dir, paste0(run_name, ".csv")),
  korea_csv  = file.path(output_dir, paste0(run_name, "_korea.csv")),
  after_csv  = file.path(output_dir, "variables_after_unit_conversion.csv"),
  mapping    = mapping_path,
  template   = template_path
)
dat_files <- list.files(output_dir, pattern = paste0("^", run_name, "_project_.*\\.dat$"),
                        full.names = TRUE)
paths$dat <- if (length(dat_files) > 0) dat_files[order(file.mtime(dat_files), decreasing = TRUE)[1]] else ""

cat("=== Step5 inputs ===\n")
for (nm in names(paths)) {
  p <- paths[[nm]]
  cat(sprintf("  %-11s %s %s\n", nm,
              ifelse(file.exists(p) & nzchar(p), "OK  ", "MISSING"),
              ifelse(nzchar(p), basename(p), "")))
}
mtime <- function(p) if (nzchar(p) && file.exists(p)) file.mtime(p) else NA
if (!is.na(mtime(paths$step1_xlsx)) && !is.na(mtime(paths$step2_csv)) &&
    mtime(paths$step1_xlsx) > mtime(paths$step2_csv)) {
  cat("WARNING: step1 xlsx is newer than step2 csv -- step2 output may be stale\n")
}
if (!is.na(mtime(paths$korea_csv)) && !is.na(mtime(paths$after_csv)) &&
    mtime(paths$korea_csv) > mtime(paths$after_csv)) {
  cat("WARNING: korea csv is newer than step4 output -- step4 output may be stale\n")
}
if (!is.na(mtime(paths$mapping)) && !is.na(mtime(paths$after_csv)) &&
    mtime(paths$mapping) > mtime(paths$after_csv)) {
  cat("WARNING: mapping xlsx is newer than step4 output -- step4 output may be stale\n")
}
#####################################

########## Run checkpoints ##########
all_results <- list()
all_mm <- list()
all_unmapped <- NULL

add <- function(res) {
  all_results[[length(all_results) + 1]] <<- res$results
  if (!is.null(res$mismatches)) all_mm[[length(all_mm) + 1]] <<- res$mismatches
  if (!is.null(res$unmapped)) all_unmapped <<- bind_rows(all_unmapped, res$unmapped)
}
skip <- function(cp, why) {
  all_results[[length(all_results) + 1]] <<- v_result(cp, "inputs", "", "SKIP", detail = why)
}
run_safe <- function(cp, expr) {
  tryCatch(expr, error = function(e) {
    all_results[[length(all_results) + 1]] <<- v_result(cp, "error", "", "FAIL",
      n_failed = 1, detail = conditionMessage(e))
  })
}

# lazy loaders (each file read at most once)
cache <- new.env()
get_long <- function(key, path, ...) {
  if (!exists(key, envir = cache)) assign(key, load_report_long(path, ...), envir = cache)
  get(key, envir = cache)
}

if ("A" %in% checkpoints) {
  if (!file.exists(paths$dat) || !nzchar(paths$dat) || !file.exists(paths$step1_xlsx)) {
    skip("A", "needs .dat project file and step1 xlsx")
  } else run_safe("A", {
    suppressMessages(library(rgcam))
    prj <- loadProject(paths$dat)
    add(checkpoint_a(prj, get_long("step1", paths$step1_xlsx),
                     step5_aggregates, step5_tol_rel_a, max_year = final_year))
  })
}

if ("B" %in% checkpoints) {
  if (file.exists(paths$step1_xlsx) && file.exists(paths$step2_csv)) {
    run_safe("B", add(checkpoint_b1(get_long("step1", paths$step1_xlsx),
                                    get_long("step2", paths$step2_csv),
                                    step5_exceptions, step5_tol_rel_b)))
  } else skip("B", "B1 needs step1 xlsx and step2 csv")

  if (file.exists(paths$step2_csv) && file.exists(paths$korea_csv)) {
    run_safe("B", {
      pre <- get_long("step2", paths$step2_csv) %>%
        filter(Region == target_region,
               as.numeric(year) >= start_year, as.numeric(year) <= final_year)
      korea <- get_long("korea", paths$korea_csv)
      add(checkpoint_b2(pre, korea, step5_exceptions, step5_tol_rel_b))
      add(identity_b3(korea, step5_tol_rel_b))
      add(identity_b5(pre, korea, step5_b5_pairs, step5_tol_rel_b))
      add(identity_b6(pre, korea, step5_tol_rel_b))
    })
  } else skip("B", "B2 needs step2 csv and korea csv")
}

if ("C" %in% checkpoints) {
  stages <- list(step1 = paths$step1_xlsx, step2_all = paths$step2_csv,
                 step2_korea = paths$korea_csv)
  for (stage_id in names(stages)) {
    if (!file.exists(stages[[stage_id]])) { skip("C", paste(stage_id, "file missing")); next }
    run_safe("C", {
      key <- c(step1 = "step1", step2_all = "step2", step2_korea = "korea")[[stage_id]]
      add(checkpoint_c(get_long(key, stages[[stage_id]]), stage_id,
                       step5_relations, step5_known_violations, step5_tol_rel_c))
    })
  }
}

if ("D" %in% checkpoints) {
  need <- c(paths$korea_csv, paths$mapping, paths$template, paths$after_csv)
  if (!all(file.exists(need))) {
    skip("D", "needs korea csv, mapping xlsx, template xlsx and step4 output")
  } else run_safe("D", {
    mapping <- read_excel(paths$mapping) %>% rename_with(tolower)
    template_units <- read_excel(paths$template) %>% rename_with(tolower) %>%
      select(Variable = variable, target_unit = unit) %>% distinct()
    add(checkpoint_d(get_long("korea", paths$korea_csv), mapping, template_units,
                     unit_table, load_report_long(paths$after_csv, na_to_zero = FALSE),
                     step5_tol_rel_d))
  })
}
#####################################

########## Reports & summary ##########
results <- bind_rows(all_results)
mismatches <- if (length(all_mm) > 0) bind_rows(all_mm) else NULL
write_step5_reports(results, mismatches, all_unmapped, output_dir)

cat(sprintf("\n=== Step5 validation summary (run: %s, db: %s) ===\n", run_name, db_name))
labels <- c(A = "A raw-vs-report ", B = "B step1-vs-step2", C = "C tree sums     ",
            D = "D template fill ")
overall_fail <- 0
for (cp in c("A", "B", "C", "D")) {
  if (!(cp %in% checkpoints)) next
  r <- results %>% filter(checkpoint == cp)
  if (nrow(r) == 0) { cat(labels[[cp]], ": SKIP (not run)\n"); next }
  n_fail <- sum(r$status == "FAIL")
  n_warn <- sum(r$status == "WARN")
  n_skip <- sum(r$status == "SKIP")
  status <- if (n_fail > 0) "FAIL" else if (n_warn > 0) "WARN"
            else if (n_skip == nrow(r)) "SKIP" else "PASS"
  overall_fail <- overall_fail + n_fail
  cat(sprintf("%s: %s  (%d checks: %d fail, %d warn, %d skip)\n",
              labels[[cp]], status, nrow(r), n_fail, n_warn, n_skip))
}
cat("Reports:", file.path(output_dir, "step5_summary.csv"), "(+ mismatches, unmapped)\n")

if (strict && overall_fail > 0) {
  stop(sprintf("step5: %d check(s) FAILED (strict mode)", overall_fail))
}
#######################################
