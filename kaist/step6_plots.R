################################################################################
# Step 6: Report plots
#
# PURPOSE:
#   Draw report figures from the step2 Korea output.
#   Figure 1: national GHG pathway (Mt CO2eq/yr), one colored line per
#   scenario, two panels: Gross (excl. LULUCF) and Net (incl. LULUCF).
#   Uses Emissions|Kyoto Gases, which excludes international bunkers after
#   the b1 reallocation (years >= 2020; earlier years keep raw GCAM values).
#
# INPUT:  {output_dir}/{run_name}_korea.csv   (from step2)
# OUTPUT: {output_dir}/{run_name}_ghg_pathway.png / .csv
################################################################################

########## Load configuration ##########
source(file.path(getwd(), "kaist/config.R"))
########################################

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})

########## Scenario colors ##########
# Fixed scenario -> color assignment (colorblind-validated palette, fixed
# order). A scenario keeps its color no matter which subset is plotted.
scenario_order <- c("ref", "S1", "S1.1", "S0.9",
                    "S0.7_ESM", "S0.8_ESM", "S08_61", "S1_53")
palette_hex <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100",
                 "#e87ba4", "#008300", "#4a3aa7", "#e34948")
scenario_colors <- setNames(palette_hex, scenario_order)
#####################################

########## Build the GHG series ##########
korea_csv <- file.path(output_dir, paste0(run_name, "_korea.csv"))
data_korea <- read_csv(korea_csv, show_col_types = FALSE)

# Gross = total minus LULUCF (land-use CO2 + land fires); agriculture stays
# in, as in the Korean inventory. Net = total as reported.
ghg <- data_korea %>%
  filter(Variable %in% c("Emissions|Kyoto Gases",
                         "Emissions|CO2|AFOLU",
                         "Emissions|Kyoto Gases|AFOLU|Land")) %>%
  pivot_longer(cols = matches("^[0-9]{4}$"),
               names_to = "year", values_to = "value") %>%
  mutate(year = as.integer(year)) %>%
  select(Scenario, Variable, year, value) %>%
  pivot_wider(names_from = Variable, values_from = value) %>%
  transmute(
    Scenario, year,
    `Gross (excl. LULUCF)` =
      `Emissions|Kyoto Gases` - `Emissions|CO2|AFOLU` -
      `Emissions|Kyoto Gases|AFOLU|Land`,
    `Net (incl. LULUCF)`   = `Emissions|Kyoto Gases`
  ) %>%
  pivot_longer(-c(Scenario, year),
               names_to = "measure", values_to = "value") %>%
  mutate(measure = factor(measure, levels = c("Gross (excl. LULUCF)",
                                              "Net (incl. LULUCF)")))

# unknown scenario names get the unused palette slots, in order
scen_known <- intersect(scenario_order, unique(ghg$Scenario))
scen_extra <- setdiff(unique(ghg$Scenario), scenario_order)
if (length(scen_extra) > 0) {
  free_hex <- setdiff(palette_hex, scenario_colors[scen_known])
  scenario_colors <- c(scenario_colors[scen_known],
                       setNames(free_hex[seq_along(scen_extra)], scen_extra))
}
ghg$Scenario <- factor(ghg$Scenario, levels = c(scen_known, scen_extra))
##########################################

########## Plot ##########
# Line-end labels only for a few scenarios; with many they overlap, so the
# legend alone carries identity.
show_end_labels <- length(unique(ghg$Scenario)) <= 3

# Plain style on purpose: white background, standard theme_bw look.
# Same Arial-metric font on both OSes (server has Liberation Sans installed).
plot_family <- if (.Platform$OS.type == "windows") "Arial" else "Liberation Sans"

p <- ggplot(ghg, aes(year, value, color = Scenario)) +
  geom_hline(yintercept = 0, color = "gray60", linewidth = 0.3) +
  geom_line(linewidth = 0.8) +
  facet_wrap(~measure) +
  scale_color_manual(values = scenario_colors) +
  scale_x_continuous(limits = c(start_year,
                                final_year + ifelse(show_end_labels, 5, 1)),
                     breaks = seq(2010, final_year, 10)) +
  labs(title = "South Korea GHG Emissions",
       x = NULL, y = "Mt CO2eq/yr", color = NULL) +
  theme_bw(base_size = 11, base_family = plot_family) +
  theme(panel.grid.minor = element_blank(),
        legend.position = "right")

if (show_end_labels) {
  end_labels <- ghg %>% group_by(Scenario, measure) %>% filter(year == max(year))
  p <- p + geom_text(data = end_labels, aes(label = Scenario),
                     hjust = -0.15, size = 3.1, family = plot_family,
                     show.legend = FALSE)
}

png_file <- file.path(output_dir, paste0(run_name, "_ghg_pathway.png"))
ggsave(png_file, p, width = 10, height = 3.8, dpi = 150, bg = "white")

series_file <- file.path(output_dir, paste0(run_name, "_ghg_pathway.csv"))
write_csv(ghg %>% arrange(measure, Scenario, year), series_file)

cat("\n=== Step 6 Complete ===\n")
cat("Figure:", png_file, "\n")
cat("Series:", series_file, "\n")
##########################
