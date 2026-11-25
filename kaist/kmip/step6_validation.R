################################################################################
# Step 6: Validation against historical benchmarks
#
# The IAMC SWG National Scenarios Study 2 asks that the historical years of a
# submission stay close to reference statistics (population, GDP, CO2, CH4,
# primary energy, electricity; 2005-2020). The reference values, their sources
# and the tolerances are in kaist/iamc/IAMC_benchmark.csv (built by
# kaist/iamc/build_IAMC_benchmark.R; see kaist/iamc/README.md).
#
#   margin_of_error_pct = 100 * (report - benchmark) / |benchmark|
#   validation_pass     = |margin_of_error_pct| <= threshold_pct
#
# INPUT:  {output_dir}/{run_name}_korea.csv (step2). Without it (step2 left out)
#         the target_region rows of {run_name}.csv or {run_name}.xlsx (step1).
#         kaist/iamc/IAMC_benchmark.csv
# OUTPUT: sheet "validation" in the gcamreport workbook {output_dir}/{run_name}.xlsx,
#         one row per scenario, metric and year; the same table as
#         {output_dir}/{run_name}_validation.csv
#         kaist/iamc/{run_name}_validation.csv and .xlsx (sheet "validation"):
#         a copy of the table next to the benchmark
# Usage:  Rscript kaist/kmip/step6_validation.R [--strict]
# Optional settings (KAIST_CONFIG file):
#   validation_benchmark_path         another benchmark csv
#   validation_copy_dir               folder of the copy (default kaist/iamc; "" = no copy)
#   validation_default_threshold_pct  tolerance of metrics without one in the csv (default 20)
#   validation_strict                 TRUE = error exit when a check fails (same as --strict)
################################################################################

########## Load configuration ##########
source(file.path(getwd(), "kaist/core/config.R"))
########################################

suppressMessages({
  library(dplyr)
  library(tidyr)
})

strict <- isTRUE(get0("validation_strict", ifnotfound = FALSE)) ||
  "--strict" %in% commandArgs(trailingOnly = TRUE)
default_threshold <- get0("validation_default_threshold_pct", ifnotfound = 20)
is_year <- function(x) grepl("^[0-9]{4}$", x)

########## 1. Benchmark ##########
bench_path <- get0("validation_benchmark_path",
                   ifnotfound = file.path(getwd(), "kaist/iamc/IAMC_benchmark.csv"))
if (!file.exists(bench_path)) stop("step6: benchmark file not found: ", bench_path)
bench <- read.csv(bench_path, check.names = FALSE, stringsAsFactors = FALSE)
if ("Region" %in% names(bench)) bench <- bench[bench$Region == target_region, ]
if (nrow(bench) == 0) stop("step6: no benchmark rows for ", target_region, " in ", bench_path)

bench_years <- names(bench)[is_year(names(bench))]
bench_long <- bind_rows(lapply(bench_years, function(y) data.frame(
  Metrics              = bench$Metrics,
  Unit                 = bench$Unit,
  Year                 = as.integer(y),
  benchmark_value      = as.numeric(bench[[y]]),
  benchmark_datasource = as.character(bench[[paste0(y, "_datasource")]]),
  threshold_pct        = as.numeric(bench$Threshold_pct),
  threshold_strict_pct = as.numeric(bench$Threshold_strict_pct),
  stringsAsFactors = FALSE)))
##################################

########## 2. Report ##########
korea_csv <- file.path(output_dir, paste0(run_name, "_korea.csv"))
step1_csv <- file.path(output_dir, paste0(run_name, ".csv"))
workbook  <- file.path(output_dir, paste0(run_name, ".xlsx"))
report_file <- c(korea_csv, step1_csv, workbook)
report_file <- report_file[file.exists(report_file)][1]
if (is.na(report_file)) stop("step6: no report found in ", output_dir, " (run step1 / step2 first)")
report <- if (grepl("\\.xlsx$", report_file)) {
  as.data.frame(readxl::read_excel(report_file, guess_max = 1e6))
} else {
  read.csv(report_file, check.names = FALSE, stringsAsFactors = FALSE)
}
names(report) <- sub("^X([0-9]{4})$", "\\1", names(report))
report <- report[report$Region == target_region & report$Variable %in% bench$Metrics, ]
if (nrow(report) == 0) stop("step6: none of the benchmark variables found for ", target_region, " in ", report_file)
cat("Report:   ", report_file, "\nBenchmark:", bench_path, "\n")

model_years <- as.integer(names(report)[is_year(names(report))])
report_long <- report %>%
  select(Scenario, Metrics = Variable, report_unit = Unit, all_of(as.character(model_years))) %>%
  pivot_longer(all_of(as.character(model_years)), names_to = "model_year", values_to = "model_value") %>%
  mutate(model_year = as.integer(model_year), model_value = as.numeric(model_value))

# A benchmark year that is not a model year is compared with the nearest model
# year, at most one year away (GCAM 9.1 core has 2021 instead of 2020; step3
# reads 2021 as 2020 in the same way).
nearest_model_year <- function(y) {
  d <- abs(model_years - y)
  if (length(d) > 0 && min(d) <= 1) model_years[which.min(d)] else NA_integer_
}
###############################

########## 3. Margin of error ##########
unit_key <- function(u) tolower(gsub("[^A-Za-z0-9]", "", u))
add_note <- function(note, cond, text) ifelse(cond, paste0(note, ifelse(note == "", "", "; "), text), note)

validation <- tidyr::crossing(Scenario = unique(report$Scenario), bench_long) %>%
  mutate(Region = target_region,
         model_year = vapply(Year, nearest_model_year, integer(1))) %>%
  left_join(report_long, by = c("Scenario", "Metrics", "model_year")) %>%
  mutate(
    no_threshold = is.na(threshold_pct),
    threshold_pct = ifelse(no_threshold, default_threshold, threshold_pct),
    unit_ok = !is.na(report_unit) & unit_key(report_unit) == unit_key(Unit),
    margin_of_error_pct = ifelse(unit_ok, round(100 * (model_value - benchmark_value) / abs(benchmark_value), 2), NA_real_),
    validation_pass = abs(margin_of_error_pct) <= threshold_pct,
    note = "",
    note = add_note(note, is.na(benchmark_value), "no benchmark value"),
    note = add_note(note, is.na(report_unit), "variable or year not in the report"),
    note = add_note(note, !is.na(report_unit) & !unit_ok, paste0("report unit is ", report_unit)),
    note = add_note(note, !is.na(model_year) & model_year != Year, paste("report year", model_year, "used")),
    note = add_note(note, no_threshold, "default threshold (none in the IAMC document)"),
    note = add_note(note, !is.na(threshold_strict_pct) & validation_pass %in% TRUE &
                      abs(margin_of_error_pct) > threshold_strict_pct,
                    paste0("above the stricter ", threshold_strict_pct, "% bound"))) %>%
  mutate(Metrics = factor(Metrics, levels = unique(bench$Metrics)),
         Scenario = factor(Scenario, levels = unique(report$Scenario))) %>%
  arrange(Scenario, Metrics, Year) %>%
  mutate(across(c(Metrics, Scenario), as.character)) %>%
  select(Scenario, Region, Metrics, Unit, Year, model_year, model_value, benchmark_value,
         benchmark_datasource, margin_of_error_pct, threshold_pct, validation_pass, note)
########################################

########## 4. Write: csv + sheet "validation" ##########
validation_csv <- file.path(output_dir, paste0(run_name, "_validation.csv"))
write.csv(validation, validation_csv, row.names = FALSE, na = "")

# The gcamreport workbook is a plain writexl file (step1), so it is read and
# written back with the extra sheet. Steps 2 and 4 read its first sheet only.
# The copy is checked against the original before it replaces it, and the file
# time is kept (step4 warns when the step1 workbook is newer than the step2 csv).
if (file.exists(workbook)) {
  sheets <- setdiff(readxl::excel_sheets(workbook), "validation")
  book <- lapply(sheets, function(s) readxl::read_excel(workbook, sheet = s, guess_max = 1e6))
  names(book) <- sheets
  tmp <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(c(book, list(validation = validation)), tmp)
  for (s in sheets) {
    same <- all.equal(as.data.frame(readxl::read_excel(tmp, sheet = s, guess_max = 1e6)),
                      as.data.frame(book[[s]]), tolerance = 1e-12)
    if (!isTRUE(same)) stop("step6: sheet '", s, "' changed while adding the validation sheet; ",
                            workbook, " left as it was")
  }
  mtime <- file.mtime(workbook)
  if (!file.copy(tmp, workbook, overwrite = TRUE)) stop("step6: cannot write ", workbook, " (open in Excel?)")
  Sys.setFileTime(workbook, mtime)
  unlink(tmp)
  cat("Sheet 'validation' written to", workbook, "\n")
} else {
  cat("No gcamreport workbook", basename(workbook), "in the output folder: csv only\n")
}
cat("Table:", validation_csv, "\n")

# Copy of the table next to the benchmark (result files: ignored by git)
copy_dir <- get0("validation_copy_dir", ifnotfound = file.path(getwd(), "kaist/iamc"))
if (nzchar(copy_dir)) {
  copy_base <- file.path(copy_dir, paste0(run_name, "_validation"))
  file.copy(validation_csv, paste0(copy_base, ".csv"), overwrite = TRUE)
  writexl::write_xlsx(list(validation = validation), paste0(copy_base, ".xlsx"))
  cat("Copy: ", paste0(copy_base, ".csv"), "(+ .xlsx)\n")
}
########################################################

########## 5. Summary ##########
options(width = 250)
cat(sprintf("\n=== Step6 validation summary (run: %s, region: %s) ===\n", run_name, target_region))
smry <- validation %>%
  group_by(Scenario = factor(Scenario, levels = unique(Scenario))) %>%
  summarise(checks = n(), pass = sum(validation_pass %in% TRUE),
            fail = sum(validation_pass %in% FALSE), not_checked = sum(is.na(validation_pass)),
            .groups = "drop")
print(as.data.frame(smry), row.names = FALSE)
show <- validation %>% filter(!(validation_pass %in% TRUE)) %>%
  transmute(Scenario, Metrics, Year, model = signif(model_value, 4), benchmark = signif(benchmark_value, 4),
            moe_pct = margin_of_error_pct, threshold_pct, pass = validation_pass, note)
if (nrow(show) > 0) {
  cat("\nFailed or not checked:\n")
  print(as.data.frame(show), row.names = FALSE, right = FALSE)
}
cat("\n=== Step 6 Complete ===\n")

n_fail <- sum(validation$validation_pass %in% FALSE)
if (strict && n_fail > 0) stop(sprintf("step6: %d validation check(s) failed (strict mode)", n_fail))
################################
