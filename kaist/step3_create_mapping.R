################################################################################
# Step 3: Create Variable Mapping
#
# PURPOSE:
#   Map template variables to GCAM variables using simple add/subtract operations.
#   This step generates a mapping template for manual review.
#
# WHAT THIS SCRIPT DOES:
#   1. Load GCAM Korea variables and template variables
#   2. Auto-match variables using exact matching and pattern transformation
#   3. Create manual mapping template (incorporates previous mapping if exists)
#   4. User manually reviews and edits the mapping file
#
# KEY DIFFERENCE FROM STEP 2:
#   - Step 2: Creates NEW variables using coefficients (complex calculations)
#   - Step 3: Maps to EXISTING variables using simple add/subtract
#
# PREREQUISITES:
#   1. Run step2_process_data.R successfully
#   2. Have template file in project output directory
#
# OUTPUT FILES:
#   - mapping_template.xlsx: Template for manual mapping review
#
# NEXT STEP:
#   1. Manually review and edit mapping_template.xlsx
#   2. kaist/step4_fill_template.R
#
################################################################################

########## Load Configuration ##########
source(file.path(getwd(), "kaist/config.R"))
########################################

########## Libraries ##########
library(readxl)
library(dplyr)
library(writexl)
library(openxlsx)
library(stringr)
################################

########## Input Files ##########
# Template and mapping paths from config.R
# (template_path and mapping_path are set in config.R)

# Previous mapping file (for incremental updates)
mapping_output_path <- mapping_path
previous_mapping_path <- mapping_output_path
#################################

########## Load Data ##########
# Load GCAM Korea variables from step2 output
gcam_vars <- read.csv(file.path(output_dir, paste0(output_prefix, "_korea.csv")),
                      stringsAsFactors = FALSE) %>%
  distinct(Variable, Unit)

# Load template variables (normalize column names to Title Case)
template_vars <- read_excel(template_path, sheet = 1) %>%
  rename_with(str_to_title) %>%
  distinct(Region, Variable, Unit)

# Load previous mapping if exists
previous_mapping <- NULL
if (file.exists(previous_mapping_path)) {
  previous_mapping <- read_excel(previous_mapping_path)
}
###############################

########## Auto-match Variables ##########
# Transform GCAM variables to match template patterns
gcam_vars_transformed <- gcam_vars %>%
  mutate(
    Variable_transformed = Variable %>%
      str_replace_all("\\|Gases", "|Gas") %>%
      str_replace_all("\\|Solids\\|Biomass", "|Biomass")
  )

# Match all template variables with auto-matching (exact + pattern)
auto_matched <- template_vars %>%
  left_join(
    gcam_vars_transformed %>% select(Variable, Variable_transformed),
    by = c("Variable" = "Variable_transformed")
  ) %>%
  mutate(gcam_variable = ifelse(!is.na(Variable), Variable, "")) %>%
  select(Region, template_variable = Variable, gcam_variable)

# Find unmatched for best match suggestions
unmatched_df <- auto_matched %>% filter(gcam_variable == "")
##########################################

########## Function: Find Best Matches ##########
find_best_matches <- function(unmatched_df, gcam_vars, n_suggestions = 5) {
  match_results <- apply(unmatched_df, 1, function(row) {
    tgt <- tolower(row["template_variable"])
    tgt_region <- row["Region"]
    avs <- tolower(gcam_vars$Variable)
    dists <- adist(tgt, avs)
    best_idx <- order(dists)[1:min(n_suggestions, length(dists))]
    best_vars <- gcam_vars$Variable[best_idx]
    data.frame(
      Region = tgt_region,
      template_variable = row["template_variable"],
      suggested_gcam_vars = paste(best_vars, collapse = "; "),
      stringsAsFactors = FALSE
    )
  }) %>% do.call(rbind, .)
  return(match_results)
}
#################################################

########## Generate Best Matches (Optional) ##########
# Uncomment to generate suggestions for unmatched variables
# best_matches <- find_best_matches(unmatched_df, gcam_vars)
# write_xlsx(best_matches, file.path(output_dir, "best_matches.xlsx"))
######################################################

########## Create Manual Mapping Template ##########
# Start with auto-matched results
mapping_template <- auto_matched %>%
  mutate(
    original_order = row_number()  # Preserve original template order
  )

# If previous mapping exists, use it as base; otherwise create new template
if (!is.null(previous_mapping)) {
  # Use previous mapping as base and update with new auto-matched gcam_variable
  mapping_template <- mapping_template %>%
    select(-gcam_variable) %>%
    left_join(
      previous_mapping %>%
        select(template_variable, gcam_variable, gcam_variable_add, gcam_variable_subtract, exact_match),
      by = "template_variable"
    ) %>%
    mutate(
      # If not in previous mapping, fill with empty strings and calculate exact_match
      gcam_variable = ifelse(is.na(gcam_variable), "", gcam_variable),
      gcam_variable_add = ifelse(is.na(gcam_variable_add), "", gcam_variable_add),
      gcam_variable_subtract = ifelse(is.na(gcam_variable_subtract), "", gcam_variable_subtract),
      exact_match = ifelse(is.na(exact_match), template_variable == gcam_variable, exact_match)
    ) %>%
    arrange(original_order)
} else {
  # No previous mapping, create fresh template
  mapping_template <- mapping_template %>%
    mutate(
      gcam_variable_add = "",
      gcam_variable_subtract = "",
      exact_match = template_variable == gcam_variable
    )
}

# Reorder columns and remove ordering helper
mapping_template <- mapping_template %>%
  select(Region, exact_match, template_variable, gcam_variable, gcam_variable_add, gcam_variable_subtract)

# Save with column widths
wb <- createWorkbook()
addWorksheet(wb, "mapping")
writeData(wb, "mapping", mapping_template)
setColWidths(wb, "mapping", cols = 1:6, widths = c(8.5, 8.5, 48, 48, 48, 48))
saveWorkbook(wb, mapping_output_path, overwrite = TRUE)
#####################################################

cat("\n=== Step 3 Complete ===\n")
cat("Mapping template:", mapping_output_path, "\n")
cat("Next: Manually review mapping, then run kaist/step4_fill_template.R\n")

