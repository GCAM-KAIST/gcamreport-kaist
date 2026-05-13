# Split Iron and Steel Coal into Fuel and Feedstock
# Using year-specific ratios from MT data

library(readxl)
library(dplyr)
library(tidyr)
library(ggplot2)

# File paths
mt_file <- "C:/GCAM/gcamreport/kmip/DB25_output/(붙임4) KMIP2025_DB_v5_4thNov_GC_UpdatedCapacity.xlsx"
kaist_file <- "C:/GCAM/gcamreport/kmip/DB25_output/variables_after_unit_conversion.csv"
output_file <- "C:/GCAM/gcamreport/kmip/DB25_output/variables_with_coal_split.csv"

# Read MT data and calculate year-specific ratios
mt_data <- read_excel(mt_file, sheet = "data")

coal_fuel_mt <- mt_data %>%
  filter(grepl("Iron and Steel.*Coal\\|Fuel$", Variable))

coal_feedstock_mt <- mt_data %>%
  filter(grepl("Iron and Steel.*Coal\\|Feedstock$", Variable))

# Get year columns (KAIST data has 2020, 2025, 2030, 2035, 2040, 2045, 2050)
kaist_years <- c("2020", "2025", "2030", "2035", "2040", "2045", "2050")

# Calculate ratios for each year
fuel_vals <- as.numeric(coal_fuel_mt[1, kaist_years])
feed_vals <- as.numeric(coal_feedstock_mt[1, kaist_years])
total_vals <- fuel_vals + feed_vals

fuel_ratios <- ifelse(total_vals > 0, fuel_vals / total_vals, 0)
feed_ratios <- ifelse(total_vals > 0, feed_vals / total_vals, 0)

ratio_table <- data.frame(
  year = kaist_years,
  fuel_ratio = fuel_ratios,
  feedstock_ratio = feed_ratios
)

print("=== Year-specific ratios from MT data ===")
print(ratio_table)

# Read KAIST data
kaist_data <- read.csv(kaist_file)

# Find Iron and Steel Coal rows (total, not already split)
coal_total_idx <- which(kaist_data$Variable == "Final Energy|Industry|Iron and Steel|Coal")
coal_fuel_idx <- which(kaist_data$Variable == "Final Energy|Industry|Iron and Steel|Coal|Fuel")
coal_feed_idx <- which(kaist_data$Variable == "Final Energy|Industry|Iron and Steel|Coal|Feedstock")

print(paste("Found", length(coal_total_idx), "Coal total rows"))
print(paste("Found", length(coal_fuel_idx), "Coal|Fuel rows"))
print(paste("Found", length(coal_feed_idx), "Coal|Feedstock rows"))

# Year columns in KAIST data
kaist_year_cols <- paste0("X", kaist_years)

# Apply ratios to each scenario
for(i in seq_along(coal_total_idx)) {
  total_row <- coal_total_idx[i]
  scenario <- kaist_data$Scenario[total_row]

  # Find corresponding Fuel and Feedstock rows
  fuel_row <- coal_fuel_idx[kaist_data$Scenario[coal_fuel_idx] == scenario]
  feed_row <- coal_feed_idx[kaist_data$Scenario[coal_feed_idx] == scenario]

  if(length(fuel_row) == 1 && length(feed_row) == 1) {
    # Get total values
    total_values <- as.numeric(kaist_data[total_row, kaist_year_cols])

    # Calculate split values
    fuel_values <- total_values * fuel_ratios
    feed_values <- total_values * feed_ratios

    # Update the data
    kaist_data[fuel_row, kaist_year_cols] <- fuel_values
    kaist_data[feed_row, kaist_year_cols] <- feed_values

    # Set unit (same as total)
    kaist_data$Unit[fuel_row] <- kaist_data$Unit[total_row]
    kaist_data$Unit[feed_row] <- kaist_data$Unit[total_row]

    print(paste("\nScenario:", scenario))
    print("Total values:")
    print(total_values)
    print("Fuel values (calculated):")
    print(fuel_values)
    print("Feedstock values (calculated):")
    print(feed_values)
    print(paste("Sum check:", sum(fuel_values + feed_values - total_values)))
  }
}

# Save the updated data
write.csv(kaist_data, output_file, row.names = FALSE)
print(paste("\nSaved:", output_file))

# Verification plot: Compare MT vs KAIST split
# For scenario matching, use 05_nzM_Adv_plus which corresponds to nzM_Adv in MT
kaist_adv <- kaist_data %>%
  filter(Scenario == "05_nzM_Adv_plus",
         grepl("Iron and Steel.*Coal", Variable))

print("\n=== Verification: KAIST data after split (05_nzM_Adv_plus) ===")
print(kaist_adv %>% select(Variable, Unit, X2020, X2030, X2040, X2050))

# Create GCAM-only plot (no MT comparison)
plot_kaist <- kaist_adv %>%
  filter(Variable != "Final Energy|Industry|Iron and Steel|Coal") %>%
  select(Variable, all_of(kaist_year_cols)) %>%
  pivot_longer(cols = starts_with("X"), names_to = "year", values_to = "value") %>%
  mutate(
    year = as.numeric(gsub("X", "", year)),
    type = ifelse(grepl("Fuel", Variable), "Fuel", "Feedstock")
  )

p <- ggplot(plot_kaist, aes(x = year, y = value, color = type)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  labs(title = "GCAM Coal Split: Fuel vs Feedstock (nzM_Adv)",
       subtitle = "Final Energy|Industry|Iron and Steel|Coal",
       x = "Year", y = "Value (ktoe/yr)", color = "Type") +
  scale_x_continuous(breaks = seq(2020, 2050, 5)) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 18, face = "bold"),
    plot.subtitle = element_text(size = 14),
    axis.title = element_text(size = 14),
    axis.text = element_text(size = 12),
    legend.text = element_text(size = 12),
    legend.title = element_text(size = 13)
  )

ggsave("C:/GCAM/gcamreport/kmip/DB25_output/coal_split_comparison.png", p, width = 10, height = 6, dpi = 150)
print("\nSaved: coal_split_comparison.png")

# Note about different total values
print("\n=== IMPORTANT NOTE ===")
print("MT와 KAIST의 총 Coal 값이 다름 (MT: Manufacturing, KAIST: Industry 전체)")
print("비율만 MT에서 가져와서 KAIST 총량에 적용함")
print("이 방법이 타당한지는 Iron and Steel 내 Coal 사용 패턴이")
print("Manufacturing과 전체 Industry에서 동일하다고 가정할 때만 유효함")
