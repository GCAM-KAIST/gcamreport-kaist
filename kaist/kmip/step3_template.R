################################################################################
# Step 3: Fill the KMIP template
#
# PURPOSE:
#   Apply variable mappings to fill template with GCAM data.
#   This step uses the mapping (kaist/kmip/make_mapping.R) to perform simple arithmetic
#   operations and convert units to template requirements.
#
# WHAT THIS SCRIPT DOES:
#   1. Load Korea GCAM data and variable mapping
#   2. Process mapped variables (apply addition/subtraction operations)
#   3. Convert units to match template requirements
#   4. Fill complete template with all scenarios
#   5. Generate missing data report
#
# PREREQUISITES:
#   1. Run step2_adjust.R (creates Korea-specific data)
#   2. Complete manual review of mapping_template.xlsx (make_mapping.R)
#   3. Have template file in output directory
#
# OUTPUT FILES:
#   - variables_before_unit_conversion.csv: Data before unit conversion
#   - variables_after_unit_conversion.csv: Final data (COMPLETE!)
#   - {run_name}_KMIP_submission.xlsx: the same data in the submitted KMIP layout
#     (openxlsx; cell styles copied from the submission template)
#
################################################################################

########## Load Configuration ##########
source(file.path(getwd(), "kaist/core/config.R"))
########################################

########## Libraries ##########
library(readr)
library(dplyr)
library(tibble)
library(readxl)
library(writexl)
library(tidyverse)
################################


########## Input Files ##########
# GCAM data from step2 (in output/)
gcam_data_path <- file.path(output_dir, paste0(run_name, "_korea.csv"))

# Template and mapping files (at project root, not in output/)

# Year columns for processing (derived from config)
year_cols <- as.character(seq(start_year, final_year, by = 5))
year_cols <- year_cols[as.numeric(year_cols) >= 2020]  # Usually start from 2020
#################################

########## Unit Conversion Table ##########
# Shared with the step4 check -- single source of truth
source(file.path(getwd(), "kaist/kmip/modules/unit_table.R"))
###########################################

########## Load Data ##########
# Load GCAM report results
gcam_data <- read_csv(gcam_data_path, show_col_types = FALSE)

# # Remove duplicate year columns: CSV may have both "X2020" and "2020" formats.
# # Keep only the "X"-prefixed versions (which have the actual data), then rename.
# bare_year_cols <- grep("^\\d{4}$", names(gcam_data), value = TRUE)
# x_year_cols <- grep("^X\\d{4}$", names(gcam_data), value = TRUE)
# if (length(bare_year_cols) > 0 && length(x_year_cols) > 0) {
#   gcam_data <- gcam_data[, !names(gcam_data) %in% bare_year_cols]
# }

# Remove 'X' prefix from year columns if present (X2020 -> 2020)
names(gcam_data) <- gsub("^X(\\d{4})$", "\\1", names(gcam_data))

# GCAM 9.1 has no 2020 period (base year 2021): fill the template 2020 column with 2021
if (!"2020" %in% names(gcam_data) && "2021" %in% names(gcam_data)) {
  names(gcam_data)[names(gcam_data) == "2021"] <- "2020"
  message("No 2020 column: using 2021 values for the template 2020 column")
}

# Load mapping and template (normalize all column names to lowercase)
mapping <- read_excel(mapping_path) %>%
  rename_with(tolower)

template <- read_excel(template_path) %>%
  rename_with(tolower)

# Variable priority (Required/Optional) from template's 'region' column
var_priority <- template %>%
  select(Variable = variable, Priority = region) %>%
  distinct()
###############################

########## Process Variable Operations ##########
# Apply variable operations (addition/subtraction) according to mapping
mapping_valid <- mapping %>% filter(!is.na(gcam_variable) & gcam_variable != "")
new_rows_list <- list()

for (i in seq_len(nrow(mapping_valid))) {
  template_var <- mapping_valid$template_variable[i]
  gcam_var <- mapping_valid$gcam_variable[i]
  gcam_var_add <- mapping_valid$gcam_variable_add[i]
  gcam_var_subtract <- mapping_valid$gcam_variable_subtract[i]

  all_scenarios <- unique(gcam_data$Scenario)

  # Process each scenario
  for (scenario in all_scenarios) {

    # Get base variable data
    base_data <- gcam_data %>%
      filter(Variable == gcam_var, Scenario == scenario)

    if (nrow(base_data) == 0) next
    if (nrow(base_data) > 1) next  # Skip if multiple rows

    base_unit <- base_data$Unit[1]

    # Start with base data - convert to regular data frame for easier manipulation
    new_row <- as.data.frame(base_data)
    new_row$Variable <- template_var

    # Addition: Add multiple variables if specified
    if (!is.na(gcam_var_add) && gcam_var_add != "") {
      add_vars <- strsplit(gcam_var_add, ";")[[1]]
      add_vars <- trimws(add_vars)

      for (add_var in add_vars) {
        add_data <- gcam_data %>%
          filter(Variable == add_var, Scenario == scenario)

        # Treat missing data as 0 (skip silently)
        if (nrow(add_data) == 0) {
          cat(sprintf("Warning: Variable '%s' not found for scenario '%s' (treating as 0)\n",
                     add_var, scenario))
          next
        }

        # Skip if multiple rows found
        if (nrow(add_data) > 1) {
          warning(sprintf("Multiple rows for %s in scenario %s", add_var, scenario))
          next
        }

        add_unit <- add_data$Unit[1]

        # Check unit consistency
        if (add_unit != base_unit) {
          warning(sprintf("Unit mismatch in addition: %s (%s) + %s (%s)",
                         gcam_var, base_unit, add_var, add_unit))
          next
        }

        # Add values for all year columns
        for (year_col in year_cols) {
          if (year_col %in% names(new_row) && year_col %in% names(add_data)) {
            new_row[[year_col]] <- new_row[[year_col]] + add_data[[year_col]][1]
          }
        }
      }
    }

    # Subtraction: Subtract multiple variables if specified
    if (!is.na(gcam_var_subtract) && gcam_var_subtract != "") {
      subtract_vars <- strsplit(gcam_var_subtract, ";")[[1]]
      subtract_vars <- trimws(subtract_vars)

      for (subtract_var in subtract_vars) {
        subtract_data <- gcam_data %>%
          filter(Variable == subtract_var, Scenario == scenario)

        # Treat missing data as 0 (skip silently)
        if (nrow(subtract_data) == 0) {
          cat(sprintf("Variable '%s' not found for scenario '%s' (treating as 0)\n",
                     subtract_var, scenario))
          next
        }

        # Skip if multiple rows found
        if (nrow(subtract_data) > 1) {
          warning(sprintf("Multiple rows for %s in scenario %s", subtract_var, scenario))
          next
        }

        subtract_unit <- subtract_data$Unit[1]

        # Check unit consistency
        if (subtract_unit != base_unit) {
          warning(sprintf("Unit mismatch in subtraction: %s (%s) - %s (%s)",
                         gcam_var, base_unit, subtract_var, subtract_unit))
          next
        }

        # Subtract values for all year columns
        for (year_col in year_cols) {
          if (year_col %in% names(new_row) && year_col %in% names(subtract_data)) {
            new_row[[year_col]] <- new_row[[year_col]] - subtract_data[[year_col]][1]
          }
        }
      }
    }

    new_rows_list[[length(new_rows_list) + 1]] <- new_row
  }
}

# Combine all processed variables
new_rows_df <- bind_rows(new_rows_list)

# Get list of template variables from mapping
template_variables <- unique(mapping_valid$template_variable)
newly_generated_vars <- unique(new_rows_df$Variable)

# Filter original template variables (exclude newly generated ones to avoid duplicates)
original_template_vars <- gcam_data %>%
  filter(Variable %in% template_variables,
          !(Variable %in% newly_generated_vars))

# Combine original + new variables
all_variables_original <- bind_rows(original_template_vars, new_rows_df)

# Replace Region with Required/Optional priority
all_variables_original <- all_variables_original %>%
  select(-Region) %>%
  left_join(var_priority %>% rename(Region = Priority), by = "Variable") %>%
  relocate(Region, .after = Scenario)

# Save before unit conversion
write_csv(all_variables_original,
          file.path(output_dir, "variables_before_unit_conversion.csv"),
          na = "")
##################################################

########## Unit Conversion ##########
# Create unit mapping from template
# Note: template has lowercase column names after rename_with(tolower)
template_units <- template %>%
  select(Variable = variable, target_unit = unit) %>%
  distinct()

# Convert to long format
df_long <- all_variables_original %>%
  pivot_longer(
    cols = all_of(year_cols),
    names_to = "Year",
    values_to = "Value"
  )

# Join with template to get target units
df_with_target <- df_long %>%
  left_join(template_units, by = "Variable")

# Apply unit conversion
df_converted_long <- df_with_target %>%
  rowwise() %>%
  mutate(
    # Find conversion factor
    conversion_factor = {
      if (is.na(target_unit) || is.na(Unit) || Unit == target_unit) {
        1.0
      } else {
        conv_row <- unit_table %>% filter(from == Unit, to == target_unit)
        if (nrow(conv_row) > 0) {
          conv_row$factor[1]
        } else {
          cat(sprintf("Missing conversion: %s (%s -> %s)\n", Variable, Unit, target_unit))
          1.0
        }
      }
    },

    # Apply conversion
    Value_new = Value * conversion_factor,

    # Update unit if conversion applied
    Unit_new = if_else(!is.na(target_unit) && conversion_factor != 1.0, target_unit, Unit)
  ) %>%
  ungroup() %>%
  select(-conversion_factor, -target_unit, -Unit, -Value) %>%
  rename(Unit = Unit_new, Value = Value_new)

# Convert back to wide format
df_after <- df_converted_long %>%
  pivot_wider(
    names_from = Year,
    values_from = Value
  )
######################################

########## Fill Complete Template ##########
# Get the variable order from template (preserve original order)
template_var_order <- unique(template$variable)
all_scenarios <- unique(gcam_data$Scenario)

# Create complete skeleton: all template variables x all scenarios
complete_skeleton <- expand.grid(
  Variable = template_var_order,
  Scenario = all_scenarios,
  stringsAsFactors = FALSE
)

# Join with converted data
df_complete <- complete_skeleton %>%
  left_join(df_after, by = c("Variable", "Scenario"))

# Fill in missing columns with appropriate defaults
df_final <- df_complete %>%
  mutate(Model = coalesce(Model, first(na.omit(df_after$Model)))) %>%
  select(-any_of("Region")) %>%
  left_join(var_priority %>% rename(Region = Priority), by = "Variable") %>%
  relocate(Region, .after = Scenario)

# Reorder columns to match expected format
col_order <- c("Model", "Scenario", "Region", "Variable", "Unit", year_cols)
df_final <- df_final %>% select(any_of(col_order))

# Sort by template variable order
df_final <- df_final %>%
  mutate(Variable = factor(Variable, levels = template_var_order)) %>%
  arrange(Scenario, Variable) %>%
  mutate(Variable = as.character(Variable))
############################################

########## Generate Reports ##########
required_vars <- var_priority %>% filter(Priority == "Required") %>% pull(Variable)
optional_vars <- var_priority %>% filter(Priority == "Optional") %>% pull(Variable)

# Check missing variables per scenario with priority breakdown
missing_detail <- df_final %>%
  rowwise() %>%
  mutate(all_years_missing = all(is.na(c_across(all_of(year_cols))))) %>%
  ungroup() %>%
  left_join(var_priority, by = "Variable") %>%
  mutate(Priority = coalesce(Priority, "Other"))

missing_report <- missing_detail %>%
  group_by(Scenario, Priority) %>%
  summarise(
    missing = sum(all_years_missing),
    total = n(),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = Priority, values_from = c(missing, total), values_fill = 0)

# Save after conversion with complete variable list
write_csv(df_final,
          file.path(output_dir, "variables_after_unit_conversion.csv"),
          na = "")

cat("\n=== Step 3 Complete ===\n")
cat("Output:", file.path(output_dir, "variables_after_unit_conversion.csv"), "\n")

cat("\n=== Coverage report by scenario ===\n")
for (i in seq_len(nrow(missing_report))) {
  scen <- missing_report$Scenario[i]
  cat(sprintf("\n  [%s]\n", scen))

  # Total
  total_all <- length(template_var_order)
  missing_all <- sum(missing_detail$all_years_missing[missing_detail$Scenario == scen])
  covered_all <- total_all - missing_all
  cat(sprintf("    Total:    %d / %d covered (%.1f%%)\n",
              covered_all, total_all, covered_all / total_all * 100))

  # Required
  total_req <- length(required_vars)
  missing_req <- sum(missing_detail$all_years_missing[
    missing_detail$Scenario == scen & missing_detail$Variable %in% required_vars])
  covered_req <- total_req - missing_req
  cat(sprintf("    Required: %d / %d covered (%.1f%%)\n",
              covered_req, total_req, covered_req / total_req * 100))

  # Optional
  total_opt <- length(optional_vars)
  missing_opt <- sum(missing_detail$all_years_missing[
    missing_detail$Scenario == scen & missing_detail$Variable %in% optional_vars])
  covered_opt <- total_opt - missing_opt
  cat(sprintf("    Optional: %d / %d covered (%.1f%%)\n",
              covered_opt, total_opt, covered_opt / total_opt * 100))
}
########## Submission workbook ##########
# Same data in the submitted KMIP layout (sheet "Template(제출용)"): the main rows
# of every scenario one block after another, then the "Added" rows of every
# scenario. Cell styles are copied from the template block; missing values are
# written as 0, as in the past GC submissions.
write_submission <- function(template_path, csv_path, out_path, model = "GC") {
  sheet <- "Template(제출용)"
  df <- read.csv(csv_path, check.names = FALSE, stringsAsFactors = FALSE)
  df <- df[!duplicated(paste(df$Scenario, df$Variable)), ]
  rownames(df) <- paste(df$Scenario, df$Variable)
  wb  <- openxlsx::loadWorkbook(template_path)
  # readxl for the cell text (openxlsx::read.xlsx turns Korean inline strings into &#...; entities)
  tpl <- as.data.frame(readxl::read_excel(template_path, sheet = sheet, col_names = FALSE,
                                          col_types = "text", .name_repair = "minimal"),
                       stringsAsFactors = FALSE)
  header <- sub("\\.0+$", "", as.character(unlist(tpl[1, ])))
  block  <- tpl[-1, , drop = FALSE]
  year_cols <- which(grepl("^[0-9]{4}$", header))
  col <- function(nm) which(tolower(header) == tolower(nm))[1]
  is_added <- !is.na(block[[col("Region")]]) & block[[col("Region")]] == "Added"
  scens <- unique(df$Scenario)

  fill_block <- function(scen, rows) {
    b <- block[rows, , drop = FALSE]
    b[[col("model")]]    <- model
    b[[col("scenario")]] <- scen
    keys <- paste(scen, b[[col("variable")]])
    for (j in year_cols) {
      v <- suppressWarnings(as.numeric(df[keys, header[j]]))
      v[is.na(v)] <- 0
      b[[j]] <- v
    }
    b
  }
  main_rows <- which(!is_added); added_rows <- which(is_added)
  out <- do.call(rbind, c(lapply(scens, fill_block, rows = main_rows),
                          lapply(scens, fill_block, rows = added_rows)))
  # template block row behind each output row, for the style copy below
  tpl_of_out <- c(rep(main_rows, length(scens)), rep(added_rows, length(scens)))

  openxlsx::deleteData(wb, sheet, cols = seq_along(header), rows = 2:(nrow(block) + 1), gridExpand = TRUE)
  openxlsx::writeData(wb, sheet, out, startRow = 2, colNames = FALSE)
  for (s in wb$styleObjects) {
    if (s$sheet != sheet) next
    for (cc in unique(s$cols)) {
      tpl_rows <- s$rows[s$cols == cc] - 1          # sheet row 2 = block row 1
      target <- which(tpl_of_out %in% tpl_rows) + 1
      if (length(target) > 0)
        openxlsx::addStyle(wb, sheet, s$style, rows = target, cols = cc, gridExpand = TRUE, stack = FALSE)
    }
  }
  openxlsx::addFilter(wb, sheet, rows = 1, cols = seq_along(header))
  openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
  drop_dangling_rels(out_path)
  cat(sprintf("KMIP submission workbook: %s (%d rows, %d scenarios)\n", out_path, nrow(out), length(scens)))
}
# openxlsx leaves a drawing relationship in every sheet of a loaded workbook but
# writes no drawing file. Excel ignores that; openpyxl and some other readers
# refuse the file. Remove the relationships whose target does not exist.
drop_dangling_rels <- function(xlsx) {
  xlsx <- normalizePath(xlsx)
  d <- tempfile("xlsx_"); dir.create(d)
  zip::unzip(xlsx, exdir = d)
  parts <- list.files(d, recursive = TRUE, all.files = TRUE)
  for (r in list.files(file.path(d, "xl/worksheets/_rels"), full.names = TRUE)) {
    s <- paste(readLines(r, warn = FALSE), collapse = "\n")
    for (rel in regmatches(s, gregexpr("<Relationship [^>]*/>", s))[[1]]) {
      target <- sub("^\\.\\./", "xl/", sub('.*Target="([^"]+)".*', "\\1", rel))
      if (!target %in% parts) s <- sub(rel, "", s, fixed = TRUE)
    }
    writeLines(s, r)
  }
  zip::zip(xlsx, files = parts, root = d, mode = "mirror")
  unlink(d, recursive = TRUE)
}
submission_path <- file.path(output_dir, paste0(run_name, "_KMIP_submission.xlsx"))
write_submission(submission_template_path,
                 file.path(output_dir, "variables_after_unit_conversion.csv"), submission_path)
#########################################

cat("\nNext: Run kaist/kmip/step4_check.R\n")
######################################

