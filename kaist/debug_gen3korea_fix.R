# Compare Primary Energy|Nuclear with and without Gen_III_Korea fix
library(tidyverse)
library(openxlsx)
library(here)
library(rgcam)

source(file.path(here(), "kaist/config.R"))

# Load project
prj_files <- list.files(project_dir, pattern = ".*project_.*[.]dat$", full.names = TRUE)
prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
prj <- loadProject(prj_file)

# Load template (manual result)
template <- read.xlsx(template_path, sheet = 1)

# Load current step4 output (with Gen_III_Korea fix)
step4_result <- read.csv(file.path(output_dir, "variables_after_unit_conversion.csv"))

# Get Gen_III_Korea generation
elec_gen <- getQuery(prj, "elec gen by gen tech")
gen3_korea <- elec_gen %>%
  filter(region == "South Korea", technology == "Gen_III_Korea") %>%
  select(scenario, year, value) %>%
  pivot_wider(names_from = year, values_from = value)

cat("=== Gen_III_Korea generation (EJ) ===\n")
print(gen3_korea)

# Get current kaist_report.csv (with fix applied)
raw_data <- read.csv(file.path(output_dir, "kaist_report.csv"))
nuclear_with_fix <- raw_data %>%
  filter(Region == "South Korea", Variable == "Primary Energy|Nuclear") %>%
  select(Scenario, starts_with("X20"))

# Calculate what it would be WITHOUT the fix
nuclear_without_fix <- nuclear_with_fix
year_cols <- names(nuclear_without_fix)[grepl("^X20", names(nuclear_without_fix))]

for (i in 1:nrow(nuclear_without_fix)) {
  scen <- nuclear_without_fix$Scenario[i]
  gen3k_row <- gen3_korea[gen3_korea$scenario == scen, ]
  if (nrow(gen3k_row) > 0) {
    for (yr_col in year_cols) {
      yr <- sub("X", "", yr_col)
      if (yr %in% names(gen3k_row)) {
        nuclear_without_fix[i, yr_col] <- as.numeric(nuclear_without_fix[i, yr_col]) -
                                          as.numeric(gen3k_row[[yr]])
      }
    }
  }
}

# Template values
template_nuclear <- template %>%
  filter(grepl("Primary Energy[|]Nuclear$", variable)) %>%
  select(scenario, `2020`, `2025`, `2030`, `2035`, `2040`, `2045`, `2050`)

cat("\n========================================\n")
cat("=== Comparison: Primary Energy|Nuclear ===\n")
cat("========================================\n")

# Convert EJ to ktoe (1 EJ = 23884.59 ktoe)
# But step4 uses different conversion, let's check
cat("\nNote: step4 output is in ktoe, kaist_report is in EJ\n")
cat("Conversion: 1 EJ = 23884.59 ktoe\n")

# Compare for 05_nzM_Adv_plus scenario
cat("\n=== Scenario: 05_nzM_Adv_plus vs nzM+_Adv ===\n")
cat("(assuming these are equivalent scenarios)\n\n")

# Template for nzM+_Adv
template_row <- template_nuclear[template_nuclear$scenario == "nzM+_Adv", ]

# Auto with fix (EJ -> ktoe)
auto_with <- nuclear_with_fix[nuclear_with_fix$Scenario == "05_nzM_Adv_plus", ]
auto_without <- nuclear_without_fix[nuclear_without_fix$Scenario == "05_nzM_Adv_plus", ]

years <- c("2020", "2025", "2030", "2035", "2040", "2050")

comparison <- data.frame(
  Year = years,
  Template_ktoe = as.numeric(template_row[1, years]),
  Auto_WithFix_EJ = NA,
  Auto_WithoutFix_EJ = NA,
  Auto_WithFix_ktoe = NA,
  Auto_WithoutFix_ktoe = NA,
  Diff_WithFix_ktoe = NA,
  Diff_WithoutFix_ktoe = NA
)

for (i in 1:length(years)) {
  yr <- years[i]
  yr_col <- paste0("X", yr)

  comparison$Auto_WithFix_EJ[i] <- as.numeric(auto_with[[yr_col]])
  comparison$Auto_WithoutFix_EJ[i] <- as.numeric(auto_without[[yr_col]])
  comparison$Auto_WithFix_ktoe[i] <- comparison$Auto_WithFix_EJ[i] * 23884.59
  comparison$Auto_WithoutFix_ktoe[i] <- comparison$Auto_WithoutFix_EJ[i] * 23884.59
  comparison$Diff_WithFix_ktoe[i] <- comparison$Auto_WithFix_ktoe[i] - comparison$Template_ktoe[i]
  comparison$Diff_WithoutFix_ktoe[i] <- comparison$Auto_WithoutFix_ktoe[i] - comparison$Template_ktoe[i]
}

print(comparison)

cat("\n=== Summary ===\n")
cat("Mean Absolute Diff WITH fix:   ", round(mean(abs(comparison$Diff_WithFix_ktoe)), 2), "ktoe\n")
cat("Mean Absolute Diff WITHOUT fix:", round(mean(abs(comparison$Diff_WithoutFix_ktoe)), 2), "ktoe\n")

cat("\n=== Which is closer to template? ===\n")
with_fix_closer <- sum(abs(comparison$Diff_WithFix_ktoe) < abs(comparison$Diff_WithoutFix_ktoe))
without_fix_closer <- sum(abs(comparison$Diff_WithoutFix_ktoe) < abs(comparison$Diff_WithFix_ktoe))
cat("Years where WITH fix is closer:", with_fix_closer, "\n")
cat("Years where WITHOUT fix is closer:", without_fix_closer, "\n")

if (mean(abs(comparison$Diff_WithFix_ktoe)) < mean(abs(comparison$Diff_WithoutFix_ktoe))) {
  cat("\n>>> Gen_III_Korea fix IMPROVES accuracy <<<\n")
} else {
  cat("\n>>> Gen_III_Korea fix REDUCES accuracy <<<\n")
}

cat("\n=== Also compare Ref_Con ===\n")
template_ref <- template_nuclear[grepl("Ref", template_nuclear$scenario, ignore.case = TRUE), ]
if (nrow(template_ref) == 0) {
  cat("No Ref scenario in template\n")
} else {
  print(template_ref)
}

auto_ref_with <- nuclear_with_fix[nuclear_with_fix$Scenario == "Ref_Con", ]
cat("\nRef_Con (with fix) in EJ:\n")
print(auto_ref_with)
