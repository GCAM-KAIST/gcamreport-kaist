################################################################################
# Compare Vehicle Capacity: MT vs GCAM
#
# PURPOSE:
#   Create comparison charts for vehicle capacity (thousand vehicles)
#   between MT model and GCAM-derived results for presentation.
#
# INPUT:
#   - MT data: (붙임4) KMIP2025_DB_v5_4thNov_GC_UpdatedCapacity.xlsx (data sheet)
#   - GCAM data: variables_after_unit_conversion.csv
#
# OUTPUT:
#   - PNG charts in output_dir
#
################################################################################

########## Load Configuration ##########
source(file.path(getwd(), "kaist/config.R"))
########################################

########## Libraries ##########
library(dplyr)
library(tidyr)
library(readxl)
library(ggplot2)
library(scales)
################################

########## Load Data ##########
# MT data (from Excel)
mt_file <- file.path(output_dir, "(붙임4) KMIP2025_DB_v5_4thNov_GC_UpdatedCapacity.xlsx")
mt_raw <- read_excel(mt_file, sheet = "data")

# GCAM data (from CSV) - use kaist_report_korea.csv which has 2015 data and vehicle conversion
gcam_file <- file.path(output_dir, "kaist_report_korea.csv")
gcam_raw <- read.csv(gcam_file, stringsAsFactors = FALSE, check.names = FALSE)
################################

########## Prepare Data ##########
# Filter transport capacity variables
# MT uses Capacity|Transport|Road|... format
# GCAM uses Energy Service|Transportation|... format (converted to thousand vehicles in step2)
mt_transport_vars <- c(
  "Capacity|Transport|Road",
  "Capacity|Transport|Road|LDV|BEV",
  "Capacity|Transport|Road|LDV|FCEV",
  "Capacity|Transport|Road|LDV|HEV",
  "Capacity|Transport|Road|LDV|ICEV",
  "Capacity|Transport|Road|MHDV|BEV",
  "Capacity|Transport|Road|MHDV|FCEV",
  "Capacity|Transport|Road|MHDV|HEV",
  "Capacity|Transport|Road|MHDV|ICEV"
)

gcam_transport_vars <- c(
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle",
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Battery-Electric",
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Fuel-Cell-Electric",
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Plug-in Hybrid",  # = HEV
  "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle|Internal Combustion",
  "Energy Service|Transportation|Freight|Truck",
  "Energy Service|Transportation|Freight|Truck|Battery-Electric",
  "Energy Service|Transportation|Freight|Truck|Plug-in Hybrid",  # = HEV
  "Energy Service|Transportation|Freight|Truck|Internal Combustion"
)

# Common years (GCAM has 5-year intervals)
# Note: MT data starts from 2020, GCAM has 2015 data (MT will have NA for 2015)
years <- c("2015", "2020", "2025", "2030", "2035", "2040", "2045", "2050")

# MT data: reshape to long format
# MT has annual data, we select only the common years
mt_year_cols <- names(mt_raw)[names(mt_raw) %in% years]
mt_data <- mt_raw %>%
  filter(Variable %in% mt_transport_vars) %>%
  select(Model, Scenario, Variable, all_of(mt_year_cols)) %>%
  pivot_longer(cols = all_of(mt_year_cols), names_to = "Year", values_to = "Value") %>%
  mutate(
    Year = as.integer(Year),
    Value = as.numeric(Value),
    Source = "MT"
  )

# GCAM data: filter and reshape
# Use Ref_Con scenario for comparison with MT nzM_Adv
gcam_year_cols <- names(gcam_raw)[names(gcam_raw) %in% years]
gcam_data <- gcam_raw %>%
  filter(Variable %in% gcam_transport_vars, Scenario == "Ref_Con") %>%
  select(Model, Scenario, Variable, all_of(gcam_year_cols)) %>%
  pivot_longer(cols = all_of(gcam_year_cols), names_to = "Year", values_to = "Value") %>%
  mutate(
    Year = as.integer(Year),
    Value = as.numeric(Value),
    Source = "GCAM (Ref)"
  )

# Also get GCAM nzM scenario for additional comparison
gcam_nzm <- gcam_raw %>%
  filter(Variable %in% gcam_transport_vars, Scenario == "05_nzM_Adv_plus") %>%
  select(Model, Scenario, Variable, all_of(gcam_year_cols)) %>%
  pivot_longer(cols = all_of(gcam_year_cols), names_to = "Year", values_to = "Value") %>%
  mutate(
    Year = as.integer(Year),
    Value = as.numeric(Value),
    Source = "GCAM (nzM)"
  )

# Combine all data
combined <- bind_rows(mt_data, gcam_data, gcam_nzm) %>%
  mutate(
    VehicleType = case_when(
      # MT format: Capacity|Transport|Road|LDV|BEV
      grepl("LDV\\|BEV$", Variable) ~ "LDV - BEV",
      grepl("LDV\\|FCEV$", Variable) ~ "LDV - FCEV",
      grepl("LDV\\|HEV$", Variable) ~ "LDV - HEV",
      grepl("LDV\\|ICEV$", Variable) ~ "LDV - ICEV",
      grepl("MHDV\\|BEV$", Variable) ~ "MHDV - BEV",
      grepl("MHDV\\|FCEV$", Variable) ~ "MHDV - FCEV",
      grepl("MHDV\\|HEV$", Variable) ~ "MHDV - HEV",
      grepl("MHDV\\|ICEV$", Variable) ~ "MHDV - ICEV",
      Variable == "Capacity|Transport|Road" ~ "Total Road",
      # GCAM format: Energy Service|Transportation|...
      grepl("Light-Duty Vehicle\\|Battery-Electric$", Variable) ~ "LDV - BEV",
      grepl("Light-Duty Vehicle\\|Fuel-Cell-Electric$", Variable) ~ "LDV - FCEV",
      grepl("Light-Duty Vehicle\\|Plug-in Hybrid$", Variable) ~ "LDV - HEV",  # GCAM Plug-in Hybrid = HEV
      grepl("Light-Duty Vehicle\\|Internal Combustion$", Variable) ~ "LDV - ICEV",
      grepl("Truck\\|Battery-Electric$", Variable) ~ "MHDV - BEV",
      grepl("Truck\\|Plug-in Hybrid$", Variable) ~ "MHDV - HEV",
      grepl("Truck\\|Internal Combustion$", Variable) ~ "MHDV - ICEV",
      Variable == "Energy Service|Transportation|Passenger|Road|Light-Duty Vehicle" ~ "LDV - Total",
      Variable == "Energy Service|Transportation|Freight|Truck" ~ "MHDV - Total",
      TRUE ~ "Other"
    ),
    Category = case_when(
      grepl("^LDV", VehicleType) ~ "Light-Duty Vehicles (LDV)",
      grepl("^MHDV", VehicleType) ~ "Medium/Heavy-Duty Vehicles (MHDV)",
      TRUE ~ "Total"
    ),
    Powertrain = case_when(
      grepl("BEV$", VehicleType) ~ "BEV",
      grepl("FCEV$", VehicleType) ~ "FCEV",
      grepl("HEV$", VehicleType) ~ "HEV",
      grepl("ICEV$", VehicleType) ~ "ICEV",
      grepl("Total$", VehicleType) ~ "Total",
      TRUE ~ "Total"
    )
  )
################################

########## Define Theme ##########
theme_presentation <- theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
    plot.subtitle = element_text(size = 12, hjust = 0.5, color = "gray40"),
    legend.position = "bottom",
    legend.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold", size = 12)
  )

# Color palette
source_colors <- c("MT" = "#E41A1C", "GCAM (Ref)" = "#377EB8", "GCAM (nzM)" = "#4DAF4A")
powertrain_colors <- c("BEV" = "#2166AC", "FCEV" = "#92C5DE", "HEV" = "#F4A582", "ICEV" = "#B2182B", "Total" = "#666666")
################################

########## Chart 1: Total Road Vehicles ##########
# Calculate total road vehicles (LDV + MHDV) for each source
total_road <- combined %>%
  filter(VehicleType %in% c("Total Road", "LDV - Total", "MHDV - Total")) %>%
  group_by(Source, Year) %>%
  summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop")

p1 <- total_road %>%
  ggplot(aes(x = Year, y = Value / 1000, color = Source, linetype = Source)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_color_manual(values = source_colors) +
  scale_y_continuous(labels = comma_format(), limits = c(0, NA)) +
  labs(
    title = "Total Road Vehicle Capacity: MT vs GCAM",
    subtitle = "South Korea, 2015-2050",
    x = "Year",
    y = "Million Vehicles",
    color = "Model",
    linetype = "Model"
  ) +
  theme_presentation

ggsave(file.path(output_dir, "chart_total_vehicles.png"), p1, width = 10, height = 6, dpi = 300)
cat("Saved: chart_total_vehicles.png\n")
################################

########## Chart 2: LDV by Powertrain (Faceted) ##########
p2 <- combined %>%
  filter(Category == "Light-Duty Vehicles (LDV)", Powertrain != "Total") %>%
  ggplot(aes(x = Year, y = Value / 1000, color = Source, linetype = Source)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  facet_wrap(~Powertrain, scales = "free_y", ncol = 2) +
  scale_color_manual(values = source_colors) +
  scale_y_continuous(labels = comma_format()) +
  labs(
    title = "Light-Duty Vehicle Capacity by Powertrain: MT vs GCAM",
    subtitle = "South Korea, 2020-2050 (million vehicles)",
    x = "Year",
    y = "Million Vehicles",
    color = "Model",
    linetype = "Model"
  ) +
  theme_presentation

ggsave(file.path(output_dir, "chart_ldv_by_powertrain.png"), p2, width = 12, height = 8, dpi = 300)
cat("Saved: chart_ldv_by_powertrain.png\n")
################################

########## Chart 3: MHDV by Powertrain (Faceted) ##########
p3 <- combined %>%
  filter(Category == "Medium/Heavy-Duty Vehicles (MHDV)", Powertrain != "Total") %>%
  ggplot(aes(x = Year, y = Value, color = Source, linetype = Source)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  facet_wrap(~Powertrain, scales = "free_y", ncol = 2) +
  scale_color_manual(values = source_colors) +
  scale_y_continuous(labels = comma_format()) +
  labs(
    title = "Medium/Heavy-Duty Vehicle Capacity by Powertrain: MT vs GCAM",
    subtitle = "South Korea, 2020-2050 (thousand vehicles)",
    x = "Year",
    y = "Thousand Vehicles",
    color = "Model",
    linetype = "Model"
  ) +
  theme_presentation

ggsave(file.path(output_dir, "chart_mhdv_by_powertrain.png"), p3, width = 12, height = 8, dpi = 300)
cat("Saved: chart_mhdv_by_powertrain.png\n")
################################

########## Chart 4: Stacked Area - LDV Composition ##########
# Prepare data for stacked area
ldv_stack <- combined %>%
  filter(Category == "Light-Duty Vehicles (LDV)", Powertrain != "Total") %>%
  mutate(Powertrain = factor(Powertrain, levels = c("ICEV", "HEV", "BEV", "FCEV")))

p4 <- ldv_stack %>%
  ggplot(aes(x = Year, y = Value / 1000, fill = Powertrain)) +
  geom_area(alpha = 0.8) +
  facet_wrap(~Source, ncol = 3) +
  scale_fill_manual(values = c("ICEV" = "#B2182B", "HEV" = "#F4A582", "BEV" = "#2166AC", "FCEV" = "#92C5DE")) +
  scale_y_continuous(labels = comma_format()) +
  labs(
    title = "LDV Fleet Composition by Powertrain",
    subtitle = "South Korea, 2015-2050",
    x = "Year",
    y = "Million Vehicles",
    fill = "Powertrain"
  ) +
  theme_presentation +
  theme(legend.position = "right")

ggsave(file.path(output_dir, "chart_ldv_composition.png"), p4, width = 14, height = 6, dpi = 300)
cat("Saved: chart_ldv_composition.png\n")
################################

########## Chart 5: Stacked Area - MHDV Composition ##########
mhdv_stack <- combined %>%
  filter(Category == "Medium/Heavy-Duty Vehicles (MHDV)", Powertrain != "Total") %>%
  mutate(Powertrain = factor(Powertrain, levels = c("ICEV", "HEV", "BEV", "FCEV")))

p5 <- mhdv_stack %>%
  ggplot(aes(x = Year, y = Value, fill = Powertrain)) +
  geom_area(alpha = 0.8) +
  facet_wrap(~Source, ncol = 3) +
  scale_fill_manual(values = c("ICEV" = "#B2182B", "HEV" = "#F4A582", "BEV" = "#2166AC", "FCEV" = "#92C5DE")) +
  scale_y_continuous(labels = comma_format()) +
  labs(
    title = "MHDV Fleet Composition by Powertrain",
    subtitle = "South Korea, 2015-2050",
    x = "Year",
    y = "Thousand Vehicles",
    fill = "Powertrain"
  ) +
  theme_presentation +
  theme(legend.position = "right")

ggsave(file.path(output_dir, "chart_mhdv_composition.png"), p5, width = 14, height = 6, dpi = 300)
cat("Saved: chart_mhdv_composition.png\n")
################################

########## Chart 6: Bar Chart - 2050 Comparison ##########
p6 <- combined %>%
  filter(Year == 2050, Powertrain != "Total", Category != "Total") %>%
  mutate(
    VehicleType = paste(gsub(" .*", "", Category), Powertrain, sep = " - "),
    VehicleType = factor(VehicleType, levels = c(
      "Light-Duty - ICEV", "Light-Duty - HEV", "Light-Duty - BEV", "Light-Duty - FCEV",
      "Medium/Heavy-Duty - ICEV", "Medium/Heavy-Duty - HEV", "Medium/Heavy-Duty - BEV", "Medium/Heavy-Duty - FCEV"
    ))
  ) %>%
  ggplot(aes(x = VehicleType, y = Value / 1000, fill = Source)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  scale_fill_manual(values = source_colors) +
  scale_y_continuous(labels = comma_format()) +
  labs(
    title = "Vehicle Capacity Comparison in 2050: MT vs GCAM",
    subtitle = "South Korea (million vehicles)",
    x = "",
    y = "Million Vehicles",
    fill = "Model"
  ) +
  theme_presentation +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 10))

ggsave(file.path(output_dir, "chart_2050_comparison.png"), p6, width = 14, height = 7, dpi = 300)
cat("Saved: chart_2050_comparison.png\n")
################################

########## Chart 7: ZEV Share (BEV + FCEV) ##########
zev_share <- combined %>%
  filter(Category != "Total", Powertrain %in% c("BEV", "FCEV", "ICEV", "HEV")) %>%
  group_by(Source, Year, Category) %>%
  summarise(
    ZEV = sum(Value[Powertrain %in% c("BEV", "FCEV")], na.rm = TRUE),
    Total = sum(Value, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(ZEV_Share = ZEV / Total * 100)

p7 <- zev_share %>%
  ggplot(aes(x = Year, y = ZEV_Share, color = Source, linetype = Source)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  facet_wrap(~Category) +
  scale_color_manual(values = source_colors) +
  scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(
    title = "Zero-Emission Vehicle (BEV + FCEV) Share",
    subtitle = "South Korea, 2015-2050",
    x = "Year",
    y = "ZEV Share (%)",
    color = "Model",
    linetype = "Model"
  ) +
  theme_presentation

ggsave(file.path(output_dir, "chart_zev_share.png"), p7, width = 12, height = 6, dpi = 300)
cat("Saved: chart_zev_share.png\n")
################################

########## Summary Table ##########
summary_table <- combined %>%
  filter(Year %in% c(2020, 2030, 2050), Category != "Total") %>%
  select(Source, Year, Category, Powertrain, Value) %>%
  pivot_wider(names_from = c(Source, Year), values_from = Value) %>%
  arrange(Category, Powertrain)

write.csv(summary_table, file.path(output_dir, "vehicle_capacity_summary.csv"), row.names = FALSE)
cat("Saved: vehicle_capacity_summary.csv\n")
################################

cat("\n=== Complete ===\n")
cat("Charts saved to:", output_dir, "\n")
