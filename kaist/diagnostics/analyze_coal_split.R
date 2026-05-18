# Analyze Iron and Steel Coal split (Fuel vs Feedstock)
# Compare MT data ratio with KAIST report data

library(readxl)
library(dplyr)
library(tidyr)
library(ggplot2)

# Define consistent colors for Fuel and Feedstock
COLORS <- c("Fuel" = "#E69F00", "Feedstock" = "#0072B2")  # Orange for Fuel, Blue for Feedstock

# File paths
mt_file <- "C:/GCAM/gcamreport/kmip/DB25_output/(붙임4) KMIP2025_DB_v5_4thNov_GC_UpdatedCapacity.xlsx"
kaist_file <- "C:/GCAM/gcamreport/kmip/DB25_output/variables_after_unit_conversion.csv"

# Read MT data (Excel data sheet)
mt_data <- read_excel(mt_file, sheet = "data")

# Find Iron and Steel Coal related variables
coal_vars <- mt_data %>%
  filter(grepl("Iron and Steel.*Coal", Variable))

print("=== MT Data: Iron and Steel Coal Variables ===")
print(unique(coal_vars$Variable))
print(paste("Scenarios:", paste(unique(coal_vars$Scenario), collapse=", ")))

# Extract Fuel and Feedstock data
coal_fuel <- coal_vars %>%
  filter(grepl("Coal\\|Fuel$", Variable))

coal_feedstock <- coal_vars %>%
  filter(grepl("Coal\\|Feedstock$", Variable))

coal_total_mt <- coal_vars %>%
  filter(grepl("Coal$", Variable) & !grepl("Fuel|Feedstock", Variable))

print("\n=== Coal Fuel (MT) ===")
print(coal_fuel %>% select(Scenario, Variable, Unit, `2020`, `2030`, `2040`, `2050`))

print("\n=== Coal Feedstock (MT) ===")
print(coal_feedstock %>% select(Scenario, Variable, Unit, `2020`, `2030`, `2040`, `2050`))

print("\n=== Coal Total (MT, if exists) ===")
print(coal_total_mt %>% select(Scenario, Variable, Unit, `2020`, `2030`, `2040`, `2050`))

# Read KAIST data
kaist_data <- read.csv(kaist_file)

# Find Iron and Steel Coal in KAIST data
kaist_coal <- kaist_data %>%
  filter(grepl("Iron and Steel.*Coal", Variable))

print("\n=== KAIST Data: Iron and Steel Coal Variables ===")
print(kaist_coal %>% select(Scenario, Variable, Unit, X2020, X2030, X2040, X2050))

# Get year columns from MT data
year_cols <- names(coal_fuel)[grepl("^[0-9]{4}$", names(coal_fuel))]
print(paste("\nYear columns:", paste(year_cols, collapse=", ")))

# Calculate ratios from MT data
scenarios <- unique(coal_fuel$Scenario)
print(paste("Scenarios in MT data:", paste(scenarios, collapse=", ")))

# Create ratio data frame
ratios_list <- list()

for(scen in scenarios) {
  fuel_row <- coal_fuel %>% filter(Scenario == scen)
  feed_row <- coal_feedstock %>% filter(Scenario == scen)

  if(nrow(fuel_row) == 1 && nrow(feed_row) == 1) {
    fuel_vals <- as.numeric(fuel_row[, year_cols])
    feed_vals <- as.numeric(feed_row[, year_cols])
    total_vals <- fuel_vals + feed_vals

    fuel_ratio <- ifelse(total_vals > 0, fuel_vals / total_vals, NA)
    feed_ratio <- ifelse(total_vals > 0, feed_vals / total_vals, NA)

    ratios_list[[scen]] <- data.frame(
      scenario = scen,
      year = as.numeric(year_cols),
      fuel_value = fuel_vals,
      feedstock_value = feed_vals,
      total = total_vals,
      fuel_ratio = fuel_ratio,
      feedstock_ratio = feed_ratio
    )
  }
}

ratios_df <- do.call(rbind, ratios_list)
rownames(ratios_df) <- NULL

print("\n=== Fuel/Feedstock Ratios by Year and Scenario ===")
print(ratios_df %>% filter(year %in% c(2020, 2025, 2030, 2035, 2040, 2045, 2050)))

# Plot 1: Ratio trends over time by scenario
p1 <- ggplot(ratios_df, aes(x = year)) +
  geom_line(aes(y = fuel_ratio, color = "Fuel"), linewidth = 1.2) +
  geom_line(aes(y = feedstock_ratio, color = "Feedstock"), linewidth = 1.2) +
  geom_point(aes(y = fuel_ratio, color = "Fuel"), size = 3) +
  geom_point(aes(y = feedstock_ratio, color = "Feedstock"), size = 3) +
  facet_wrap(~scenario, ncol = 2) +
  labs(title = "MT Data: Coal Fuel vs Feedstock Ratio Trends",
       subtitle = "Final Energy|Industry|Manufacturing|Iron and Steel|Coal",
       x = "Year", y = "Ratio", color = "Type") +
  scale_color_manual(values = COLORS) +
  scale_y_continuous(labels = scales::percent_format(), limits = c(0, 1)) +
  scale_x_continuous(breaks = seq(2020, 2050, 5)) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 18, face = "bold"),
    plot.subtitle = element_text(size = 14),
    axis.title = element_text(size = 14),
    axis.text = element_text(size = 12),
    legend.text = element_text(size = 12)
  )

ggsave("C:/GCAM/gcamreport/kmip/DB25_output/coal_ratio_trends.png", p1, width = 12, height = 8, dpi = 150)
print("\nSaved: coal_ratio_trends.png")

# Plot 2: Stacked area - absolute values
plot_data_long <- ratios_df %>%
  select(scenario, year, fuel_value, feedstock_value) %>%
  pivot_longer(cols = c(fuel_value, feedstock_value),
               names_to = "type", values_to = "value") %>%
  mutate(type = case_when(
    type == "fuel_value" ~ "Fuel",
    type == "feedstock_value" ~ "Feedstock"
  ))

p2 <- ggplot(plot_data_long, aes(x = year, y = value, fill = type)) +
  geom_area(alpha = 0.7, position = "stack") +
  facet_wrap(~scenario, ncol = 2, scales = "free_y") +
  labs(title = "MT Data: Coal Fuel vs Feedstock Absolute Values",
       subtitle = "Final Energy|Industry|Manufacturing|Iron and Steel|Coal",
       x = "Year", y = "Value (ktoe/yr)", fill = "Type") +
  scale_fill_manual(values = COLORS) +
  scale_x_continuous(breaks = seq(2020, 2050, 5)) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 18, face = "bold"),
    plot.subtitle = element_text(size = 14),
    axis.title = element_text(size = 14),
    axis.text = element_text(size = 12),
    legend.text = element_text(size = 12)
  )

ggsave("C:/GCAM/gcamreport/kmip/DB25_output/coal_absolute_values.png", p2, width = 12, height = 8, dpi = 150)
print("Saved: coal_absolute_values.png")

# Ratio stability analysis
ratio_stability <- ratios_df %>%
  group_by(scenario) %>%
  summarize(
    fuel_ratio_mean = mean(fuel_ratio, na.rm = TRUE),
    fuel_ratio_sd = sd(fuel_ratio, na.rm = TRUE),
    fuel_ratio_min = min(fuel_ratio, na.rm = TRUE),
    fuel_ratio_max = max(fuel_ratio, na.rm = TRUE),
    fuel_ratio_range = max(fuel_ratio, na.rm = TRUE) - min(fuel_ratio, na.rm = TRUE),
    cv = sd(fuel_ratio, na.rm = TRUE) / mean(fuel_ratio, na.rm = TRUE) * 100
  )

print("\n=== Ratio Stability Analysis ===")
print(ratio_stability)

cat("\n\n========== CONCLUSION ==========\n")
max_range <- max(ratio_stability$fuel_ratio_range, na.rm = TRUE)
max_cv <- max(ratio_stability$cv, na.rm = TRUE)

cat(sprintf("Max ratio range across scenarios: %.1f%%\n", max_range * 100))
cat(sprintf("Max coefficient of variation: %.1f%%\n", max_cv))

if(max_range > 0.1) {
  cat("\n[WARNING] Ratio varies significantly over time (range > 10%).\n")
  cat("Using a constant ratio may NOT be appropriate.\n")
  cat("Recommendation: Use year-specific ratios from MT data.\n")
} else {
  cat("\n[OK] Ratio is relatively stable over time (range <= 10%).\n")
  cat("Using average ratio could be acceptable.\n")
}

# Save ratios for reference
write.csv(ratios_df, "C:/GCAM/gcamreport/kmip/DB25_output/coal_fuel_feedstock_ratios.csv", row.names = FALSE)
print("\nSaved: coal_fuel_feedstock_ratios.csv")

# ============================================================
# PART 2: GCAM Query-based Fuel/Feedstock Ratio Calculation
# ============================================================
# GCAM에서 BF(고로)는 coal을 feedstock으로 사용
# EAF(전기로)는 coal을 거의 사용하지 않음
# 따라서 BF 생산 비율 ≈ Feedstock 비율로 가정

cat("\n\n========== GCAM QUERY-BASED ANALYSIS ==========\n")

gcam_xl_file <- "C:/GCAM/gcamreport/kmip/DB25_output/nzM_ironandsteel.xlsx"

# Read production by tech (Sheet1)
gcam_prod <- read_excel(gcam_xl_file, sheet = "Sheet1", skip = 1)

gcam_years <- c("2020", "2025", "2030", "2035", "2040", "2045", "2050")

# BF production (Feedstock user)
bf_prod <- gcam_prod %>%
  filter(subsector == "BLASTFUR") %>%
  summarize(across(all_of(gcam_years), ~sum(., na.rm = TRUE)))

# EAF production (minimal coal use)
eaf_prod <- gcam_prod %>%
  filter(grepl("EAF", subsector)) %>%
  summarize(across(all_of(gcam_years), ~sum(., na.rm = TRUE)))

# Total production
total_prod <- gcam_prod %>%
  summarize(across(all_of(gcam_years), ~sum(., na.rm = TRUE)))

# Calculate ratios
bf_vals <- as.numeric(bf_prod)
eaf_vals <- as.numeric(eaf_prod)
total_vals <- as.numeric(total_prod)

# BF uses coal as feedstock, EAF uses minimal coal (mostly as fuel if any)
feedstock_ratio_gcam <- bf_vals / total_vals
fuel_ratio_gcam <- 1 - feedstock_ratio_gcam  # Simplified: remaining is fuel

gcam_ratios_df <- data.frame(
  source = "GCAM (BF ratio)",
  year = as.numeric(gcam_years),
  bf_production = bf_vals,
  eaf_production = eaf_vals,
  total_production = total_vals,
  feedstock_ratio = feedstock_ratio_gcam,
  fuel_ratio = fuel_ratio_gcam
)

print("\n=== GCAM-based Ratios (BF=Feedstock assumption) ===")
print(gcam_ratios_df)

# Compare MT vs GCAM ratios
mt_ratios_subset <- ratios_df %>%
  filter(year %in% as.numeric(gcam_years)) %>%
  select(year, feedstock_ratio, fuel_ratio) %>%
  mutate(source = "MT Data")

gcam_ratios_subset <- gcam_ratios_df %>%
  select(year, feedstock_ratio, fuel_ratio, source)

comparison_df <- bind_rows(mt_ratios_subset, gcam_ratios_subset)

print("\n=== MT vs GCAM Ratio Comparison ===")
print(comparison_df %>% arrange(year, source))

# Plot 3: Compare MT vs GCAM ratios
comparison_long <- comparison_df %>%
  pivot_longer(cols = c(feedstock_ratio, fuel_ratio),
               names_to = "type", values_to = "ratio") %>%
  mutate(type = case_when(
    type == "feedstock_ratio" ~ "Feedstock",
    type == "fuel_ratio" ~ "Fuel"
  ))

p3 <- ggplot(comparison_long, aes(x = year, y = ratio,
                                   color = type, linetype = source)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  labs(title = "Coal Fuel/Feedstock Ratio: MT vs GCAM (nzM_Adv)",
       subtitle = "GCAM ratio based on BF(Feedstock) vs EAF(Fuel) production share",
       x = "Year", y = "Ratio", color = "Type", linetype = "Source") +
  scale_color_manual(values = COLORS) +
  scale_y_continuous(labels = scales::percent_format(), limits = c(0, 1)) +
  scale_x_continuous(breaks = seq(2020, 2050, 5)) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 18, face = "bold"),
    plot.subtitle = element_text(size = 12),
    axis.title = element_text(size = 14),
    axis.text = element_text(size = 12),
    legend.text = element_text(size = 12)
  )

ggsave("C:/GCAM/gcamreport/kmip/DB25_output/coal_ratio_mt_vs_gcam.png",
       p3, width = 12, height = 7, dpi = 150)
print("\nSaved: coal_ratio_mt_vs_gcam.png")

# Summary comparison
cat("\n\n========== COMPARISON SUMMARY ==========\n")
cat("MT Data: Feedstock ratio relatively stable (~69-70%) until 2040,\n")
cat("         then drops sharply to 0% by 2050\n")
cat("\nGCAM Data: Feedstock ratio (= BF production share) decreases\n")
cat("           steadily from 69% (2020) to 21% (2050)\n")
cat("\n[KEY DIFFERENCE]\n")
cat("- MT: Feedstock suddenly goes to 0 in 2050\n")
cat("- GCAM: BF production decreases gradually but doesn't disappear\n")
cat("\nRecommendation: Use GCAM-based ratios for consistency with model\n")

# Save GCAM ratios
write.csv(gcam_ratios_df,
          "C:/GCAM/gcamreport/kmip/DB25_output/coal_fuel_feedstock_ratios_gcam.csv",
          row.names = FALSE)
print("\nSaved: coal_fuel_feedstock_ratios_gcam.csv")

# ============================================================
# PART 3: Query-based Fuel/Feedstock Ratio Calculation
# ============================================================
# GCAM does not distinguish coal feedstock vs fuel
# Use technology-specific ratios based on steel industry literature:
# - BF process: Coke (feedstock) ~75%, PCI (fuel) ~25%
# - EAF process: minimal coal use, mostly as fuel

cat("\n\n========== QUERY-BASED ANALYSIS ==========\n")

# Read Sheet4 - industry final energy by tech and fuel
df4 <- read_excel(gcam_xl_file, sheet = "Sheet4", skip = 1)
is_df4 <- df4 %>% filter(grepl("iron", sector, ignore.case = TRUE))

# Coal use by technology
coal_by_tech <- is_df4 %>%
  filter(grepl("coal", input, ignore.case = TRUE)) %>%
  group_by(technology) %>%
  summarize(across(all_of(gcam_years), ~sum(., na.rm = TRUE)), .groups = "drop")

print("\n=== Coal use by Technology (EJ) ===")
print(coal_by_tech)

# Technology-specific feedstock ratios (literature-based assumptions)
# BF: ~75% feedstock (coke for reduction), ~25% fuel (PCI for heat)
# BF with H2: ~50% feedstock (H2 partially replaces coke)
# EAF: 0% feedstock (coal used only for heating, very small amount)
tech_fs_ratio <- c(
  "BLASTFUR" = 0.75,
  "BLASTFUR CCS" = 0.75,
  "BLASTFUR with hydrogen" = 0.50,
  "EAF with DRI" = 0,
  "EAF with DRI CCS" = 0
)

# Calculate weighted feedstock/fuel split
total_coal <- colSums(coal_by_tech[, gcam_years], na.rm = TRUE)
feedstock_coal <- rep(0, length(gcam_years))
fuel_coal <- rep(0, length(gcam_years))

for (i in 1:nrow(coal_by_tech)) {
  tech <- coal_by_tech$technology[i]
  coal_vals <- as.numeric(coal_by_tech[i, gcam_years])
  fs_ratio <- tech_fs_ratio[tech]
  if (!is.na(fs_ratio)) {
    feedstock_coal <- feedstock_coal + coal_vals * fs_ratio
    fuel_coal <- fuel_coal + coal_vals * (1 - fs_ratio)
  }
}

query_ratios_df <- data.frame(
  source = "GCAM (Query-based)",
  year = as.numeric(gcam_years),
  total_coal = as.numeric(total_coal),
  feedstock = feedstock_coal,
  fuel = fuel_coal,
  feedstock_ratio = feedstock_coal / as.numeric(total_coal),
  fuel_ratio = fuel_coal / as.numeric(total_coal)
)

print("\n=== Query-based Feedstock/Fuel Split ===")
print(query_ratios_df)

# Compare all three methods: MT, GCAM (BF ratio), GCAM (Query-based)
query_ratios_subset <- query_ratios_df %>%
  select(year, feedstock_ratio, fuel_ratio, source)

all_comparison <- bind_rows(
  mt_ratios_subset,
  gcam_ratios_subset,
  query_ratios_subset
)

print("\n=== All Methods Comparison ===")
print(all_comparison %>% arrange(year, source))

# Plot 4: Compare all three methods
all_comparison_long <- all_comparison %>%
  pivot_longer(cols = c(feedstock_ratio, fuel_ratio),
               names_to = "type", values_to = "ratio") %>%
  mutate(type = case_when(
    type == "feedstock_ratio" ~ "Feedstock",
    type == "fuel_ratio" ~ "Fuel"
  ))

p4 <- ggplot(all_comparison_long %>% filter(type == "Feedstock"),
             aes(x = year, y = ratio, color = source)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  labs(title = "Coal Feedstock Ratio: Three Methods Compared (nzM_Adv)",
       subtitle = "MT Data vs GCAM BF-ratio vs GCAM Query-based",
       x = "Year", y = "Feedstock Ratio", color = "Method") +
  scale_y_continuous(labels = scales::percent_format(), limits = c(0, 1)) +
  scale_x_continuous(breaks = seq(2020, 2050, 5)) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 18, face = "bold"),
    plot.subtitle = element_text(size = 12),
    axis.title = element_text(size = 14),
    axis.text = element_text(size = 12),
    legend.text = element_text(size = 11)
  )

ggsave("C:/GCAM/gcamreport/kmip/DB25_output/coal_ratio_all_methods.png",
       p4, width = 12, height = 7, dpi = 150)
print("\nSaved: coal_ratio_all_methods.png")

# Final summary
cat("\n\n========== FINAL SUMMARY ==========\n")
cat("Three methods for Coal Feedstock/Fuel split:\n\n")
cat("1. MT Data:\n")
cat("   - Feedstock ~70% (2020-2040) -> 0% (2050)\n")
cat("   - Inconsistent with GCAM (sudden drop)\n\n")
cat("2. GCAM BF Production Ratio:\n")
cat("   - Feedstock = BF share of total steel production\n")
cat("   - 69% (2020) -> 21% (2050), gradual decline\n")
cat("   - Problem: Assumes all BF coal is feedstock\n\n")
cat("3. GCAM Query-based (RECOMMENDED):\n")
cat("   - Tech-specific ratios: BF=75%, BF+H2=50%, EAF=0%\n")
cat("   - Feedstock ~74-75% (stable across years)\n")
cat("   - Most consistent with steel industry physics\n\n")
cat("Recommendation: Use Query-based method for GCAM consistency\n")

# Save Query-based ratios
write.csv(query_ratios_df,
          "C:/GCAM/gcamreport/kmip/DB25_output/coal_fuel_feedstock_ratios_query.csv",
          row.names = FALSE)
print("\nSaved: coal_fuel_feedstock_ratios_query.csv")

# ============================================================
# PART 4: MT vs Query-based Absolute Values Comparison Graph
# ============================================================

cat("\n\n========== MT vs QUERY-BASED COMPARISON ==========\n")

# Read KAIST data and apply both methods for comparison
kaist_data <- read.csv(kaist_file)

# Get Coal total for nzM_Adv scenario
kaist_coal_total <- kaist_data %>%
  filter(Scenario == "05_nzM_Adv_plus",
         Variable == "Final Energy|Industry|Iron and Steel|Coal")

kaist_year_cols <- paste0("X", gcam_years)
coal_total_values <- as.numeric(kaist_coal_total[1, kaist_year_cols])

# MT-based split
mt_fuel_ratios <- ratios_df %>%
  filter(year %in% as.numeric(gcam_years)) %>%
  pull(fuel_ratio)
mt_feed_ratios <- ratios_df %>%
  filter(year %in% as.numeric(gcam_years)) %>%
  pull(feedstock_ratio)

mt_split <- data.frame(
  method = "MT",
  year = as.numeric(gcam_years),
  Fuel = coal_total_values * mt_fuel_ratios,
  Feedstock = coal_total_values * mt_feed_ratios
)

# Query-based split
query_fuel_ratios <- query_ratios_df$fuel_ratio
query_feed_ratios <- query_ratios_df$feedstock_ratio

query_split <- data.frame(
  method = "Query-based",
  year = as.numeric(gcam_years),
  Fuel = coal_total_values * query_fuel_ratios,
  Feedstock = coal_total_values * query_feed_ratios
)

# Combine for plotting
comparison_split <- bind_rows(mt_split, query_split) %>%
  pivot_longer(cols = c(Fuel, Feedstock), names_to = "type", values_to = "value")

print("\n=== MT vs Query-based Absolute Values (ktoe/yr) ===")
print(comparison_split %>% pivot_wider(names_from = type, values_from = value) %>% arrange(year, method))

# Calculate percentages for labels
label_data <- comparison_split %>%
  group_by(method, year) %>%
  mutate(total = sum(value),
         pct = value / total * 100) %>%
  ungroup() %>%
  filter(type == "Feedstock") %>%
  group_by(method, year) %>%
  summarize(total = first(total), pct = first(pct), .groups = "drop")

# Plot 5: MT vs Query-based absolute values comparison
p5 <- ggplot(comparison_split, aes(x = year, y = value, fill = type)) +
  geom_bar(stat = "identity", position = "stack", alpha = 0.8) +
  geom_text(data = label_data, aes(x = year, y = total, fill = NULL,
            label = sprintf("%.0f%%", pct)),
            vjust = -0.3, size = 4, fontface = "bold") +
  facet_wrap(~method, ncol = 2) +
  labs(title = "Coal Fuel/Feedstock Split: MT vs Query-based (nzM_Adv)",
       subtitle = "Applied to KAIST Coal total: Final Energy|Industry|Iron and Steel|Coal",
       x = "Year", y = "Value (ktoe/yr)", fill = "Type") +
  scale_fill_manual(values = COLORS) +
  scale_x_continuous(breaks = seq(2020, 2050, 5)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 18, face = "bold"),
    plot.subtitle = element_text(size = 12),
    axis.title = element_text(size = 14),
    axis.text = element_text(size = 12),
    legend.text = element_text(size = 12)
  )

ggsave("C:/GCAM/gcamreport/kmip/DB25_output/coal_split_mt_vs_query.png",
       p5, width = 12, height = 7, dpi = 150)
print("\nSaved: coal_split_mt_vs_query.png")
