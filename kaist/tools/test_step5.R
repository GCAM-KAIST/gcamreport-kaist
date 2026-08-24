################################################################################
# Fault-injection self-test for step5 validation.
# Perturbs in-memory copies of the DB26 outputs and asserts each checkpoint
# detects the fault. Never touches data/ or the real pipeline outputs.
# Run from the repo root: Rscript kaist/tools/test_step5.R
################################################################################

source(file.path(getwd(), "kaist/config.R"))
suppressMessages({
  library(dplyr); library(tidyr); library(tibble)
  library(readxl); library(stringr); library(rlang)
})
source(file.path(getwd(), "kaist/modules/00_utils.R"))
source(file.path(getwd(), "kaist/unit_table.R"))
for (f in list.files(file.path(getwd(), "kaist/modules/validate"),
                     pattern = "\\.R$", full.names = TRUE)) source(f)

pass <- function(name) cat("PASS:", name, "\n")
expect <- function(cond, name) if (cond) pass(name) else stop("FAILED: ", name)

step1 <- load_report_long(file.path(output_dir, paste0(run_name, ".xlsx")))
step2 <- load_report_long(file.path(output_dir, paste0(run_name, ".csv")))
korea <- load_report_long(file.path(output_dir, paste0(run_name, "_korea.csv")))
pre <- step2 %>% filter(Region == target_region,
                        as.numeric(year) >= start_year, as.numeric(year) <= final_year)

# --- 1. checkpoint B detects a perturbed non-exception cell -------------------
poke <- step2
idx <- which(poke$Variable == "Final Energy|Industry" & poke$Region == target_region &
             poke$year == "2030")[1]
poke$value[idx] <- poke$value[idx] * 1.01
r <- checkpoint_b1(step1, poke, step5_exceptions, step5_tol_rel_b)
expect(any(r$results$status == "FAIL"), "B detects 1% perturbation of a pass-through cell")

# --- 2. checkpoint B honors exceptions (Price|Carbon may differ) --------------
poke <- step2
idx <- which(poke$Variable == "Price|Carbon")[1]
if (!is.na(idx)) {
  poke$value[idx] <- poke$value[idx] + 999
  r <- checkpoint_b1(step1, poke, step5_exceptions, step5_tol_rel_b)
  expect(!any(r$results$status == "FAIL"), "B ignores perturbation inside a1 exception")
} else pass("B exception test skipped (no Price|Carbon rows)")

# --- 3. checkpoint B warns when a module's rows are missing -------------------
poke <- korea %>% filter(!grepl("\\|[Bb]iomass\\|Liquids$", Variable))
r <- checkpoint_b2(pre, poke, step5_exceptions, step5_tol_rel_b)
expect(any(r$results$status == "WARN" & grepl("b5", r$results$check_id)),
       "B warns when b5 output rows are absent")

# --- 4. identity_b5 detects double counting (unscaled Liquids) ----------------
poke <- korea
liq <- grepl("^Final Energy(\\|.*)?\\|Liquids$", poke$Variable) &
  !grepl("\\|[Bb]iomass\\|Liquids$", poke$Variable)
poke$value[liq] <- poke$value[liq] * 1.005   # undo part of the (1-share) scaling
r <- identity_b5(pre, poke, step5_b5_pairs, step5_tol_rel_b)
expect(any(r$results$status == "FAIL"), "identity_b5 detects unscaled Liquids (double count)")

# --- 5. checkpoint C detects a broken tree sum --------------------------------
poke <- korea
idx <- which(poke$Variable == "Secondary Energy|Electricity|Coal" & poke$year == "2030")[1]
poke$value[idx] <- poke$value[idx] + 0.5
r <- checkpoint_c(poke, "step2_korea", step5_relations, step5_known_violations,
                  step5_tol_rel_c)
bad <- r$results %>% filter(check_id == "se_elec_sources")
expect(bad$status == "FAIL" && r$mismatches$year[1] == "2030",
       "C detects perturbed SE|Electricity|Coal at the exact year")

# --- 6. checkpoint D detects a perturbed template cell ------------------------
mapping <- read_excel(mapping_path) %>% rename_with(tolower)
template_units <- read_excel(template_path) %>% rename_with(tolower) %>%
  select(Variable = variable, target_unit = unit) %>% distinct()
after <- load_report_long(file.path(output_dir, "variables_after_unit_conversion.csv"),
                          na_to_zero = FALSE)
poke <- after
idx <- which(poke$Variable == "Final Energy|Industry" & poke$year == "2030" &
             !is.na(poke$value))[1]
poke$value[idx] <- poke$value[idx] * 1.02
r <- checkpoint_d(korea, mapping, template_units, unit_table, poke, step5_tol_rel_d)
expect(r$results$status == "FAIL" &&
         any(r$mismatches$note == "value_mismatch"),
       "D detects perturbed step4 output cell")

# --- 7. checkpoint A flags an unmapped technology (in-memory map override) ----
dat_files <- list.files(output_dir, pattern = paste0("^", run_name, "_project_.*\\.dat$"),
                        full.names = TRUE)
if (length(dat_files) > 0) {
  suppressMessages(library(rgcam))
  prj <- loadProject(dat_files[order(file.mtime(dat_files), decreasing = TRUE)[1]])
  broken <- load_gcam_rda("secondary_energy_map") %>%
    filter(!grepl("^PV", technology))
  r <- checkpoint_a(prj, step1, step5_aggregates %>% filter(aggregate_id == "se_elec"),
                    step5_tol_rel_a, maps = list(secondary_energy_map = broken),
                    max_year = final_year)
  expect(!is.null(r$unmapped) && any(r$unmapped$status == "unmapped" &
                                     grepl("^PV", r$unmapped$key3)),
         "A lists dropped PV tech as unmapped")
  cov <- r$results %>% filter(grepl("coverage", check_id))
  expect(cov$status == "FAIL", "A coverage FAILs on unmapped tech")
} else pass("A fault test skipped (no .dat)")

cat("\nAll step5 fault-injection tests passed.\n")
