################################################################################
# compare_h2: KMIP hydrogen rows vs values read directly from the GCAM database
#
# For every hydrogen row of the KMIP template, sums the raw rows of the step1
# project file (no gcamreport mapping, no step2 module) with explicit filters
# and compares them with the pipeline result (variables_after_unit_conversion.csv).
# Run after step3:
#   KAIST_CONFIG=kaist/kmip/config/<run>.R Rscript kaist/kmip/hydrogen/compare_h2.R \
#     [scenario] [year] [before_csv]
# scenario / year pick the figure (default: last scenario label, final_year).
# before_csv: an older variables_after_unit_conversion.csv, drawn as a third
# marker (e.g. the output before an update). The table covers all scenarios
# and the template years 2025 to final_year (2020 is the 2021 value in step3).
# Writes {output_dir}/{run_name}_h2_compare.csv and _h2_compare.png.
################################################################################

source(file.path(getwd(), "kaist/core/config.R"))
source(file.path(getwd(), "kaist/kmip/modules/unit_table.R"))
suppressMessages({ library(dplyr); library(tidyr); library(ggplot2) })

args <- commandArgs(trailingOnly = TRUE)
scen_labels <- if (exists("scenario_labels")) unname(scenario_labels) else scenarios
fig_scen   <- if (length(args) >= 1) args[1] else tail(scen_labels, 1)
fig_year   <- if (length(args) >= 2) as.numeric(args[2]) else final_year
before_csv <- if (length(args) >= 3) args[3] else NA
ej_to_ktoe <- unit_table$factor[unit_table$from == "EJ/yr" & unit_table$to == "ktoe/yr"]

########## DB direct (EJ) ##########
prj_files <- list.files(output_dir, pattern = paste0("^", run_name, "_project_.*\\.dat$"), full.names = TRUE)
prj <- rgcam::loadProject(prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]])
get_q <- function(q) rgcam::getQuery(prj, q) %>% filter(region == target_region, year >= 2025, year <= final_year)

prod <- get_q("hydrogen production by tech")
inp  <- get_q("inputs by tech")
# final energy: H2 markets bought by end-use sectors (production, delivery,
# refining, power and international bunkers are not final energy)
h2_markets <- c("H2 industrial", "H2 wholesale delivery", "H2 retail delivery",
                "H2 LDV", "H2 MHDV", "LH2", "H2 central production")
fe <- get_q("inputs by sector") %>%
  filter(input %in% h2_markets,
         !grepl("^H2 |^LH2$|^imported H2$|^refining$|_intl$|electricity", sector))

direct <- bind_rows(
  prod %>% mutate(variable = "Secondary Energy|Hydrogen|Domestic"),
  prod %>% filter(grepl("^biomass to H2", technology)) %>% mutate(variable = "Secondary Energy|Hydrogen|Domestic|Biomass"),
  prod %>% filter(technology == "gas ATR CCS") %>% mutate(variable = "Secondary Energy|Hydrogen|Domestic|Gas|w/ CCS"),
  prod %>% filter(technology == "natural gas steam reforming") %>% mutate(variable = "Secondary Energy|Hydrogen|Domestic|Gas|w/o CCS"),
  prod %>% filter(technology == "electrolysis") %>% mutate(variable = "Secondary Energy|Hydrogen|Domestic|Electricity"),
  inp %>% filter(input == "imported H2") %>% mutate(variable = "Secondary Energy|Hydrogen|Import"),
  prod %>% mutate(variable = "Secondary Energy|Hydrogen"),
  inp %>% filter(input == "imported H2") %>% mutate(variable = "Secondary Energy|Hydrogen"),
  inp %>% filter(sector == "H2 central production", input == "regional biomass") %>% mutate(variable = "Primary Energy|Biomass|Hydrogen"),
  inp %>% filter((sector == "H2 central production" & input == "regional natural gas") |
                 (subsector == "onsite production" & input == "delivered gas")) %>% mutate(variable = "Primary Energy|Gas|Hydrogen"),
  inp %>% filter(technology == "electrolysis", input %in% c("elect_td_ind", "elect_td_trn")) %>% mutate(variable = "Primary Energy|Electricity|Hydrogen"),
  fe %>% mutate(variable = "Final Energy|Hydrogen"),
  fe %>% filter(sector %in% c("iron and steel", "process heat cement", "other industrial energy use",
                              "construction energy use", "mining energy use", "ammonia", "N fertilizer",
                              "chemical energy use")) %>% mutate(variable = "Final Energy|Industry|Hydrogen"),
  fe %>% filter(sector == "iron and steel") %>% mutate(variable = "Final Energy|Industry|Iron and Steel|Hydrogen"),
  fe %>% filter(sector == "process heat cement") %>% mutate(variable = "Final Energy|Industry|Non-Metallic Minerals|Hydrogen"),
  fe %>% filter(sector %in% c("ammonia", "N fertilizer", "chemical energy use")) %>% mutate(variable = "Final Energy|Industry|Chemicals|Hydrogen"),
  fe %>% filter(sector %in% c("other industrial energy use", "construction energy use", "mining energy use")) %>%
    mutate(variable = "Final Energy|Industry|Other Sector|Hydrogen"),
  fe %>% filter(grepl("^trn_", sector)) %>% mutate(variable = "Final Energy|Transportation|Hydrogen"),
  fe %>% filter(grepl("^trn_.*road", sector)) %>% mutate(variable = "Final Energy|Transportation|Road|Hydrogen"),
  fe %>% filter(sector %in% c("trn_pass", "trn_freight"), input == "H2 MHDV") %>% mutate(variable = "Final Energy|Transportation|Rail|Hydrogen"),
  fe %>% filter(sector == "trn_freight", input == "LH2") %>% mutate(variable = "Final Energy|Transportation|Ship|Hydrogen"),
  fe %>% filter(sector == "trn_pass", input == "LH2") %>% mutate(variable = "Final Energy|Transportation|Air|Hydrogen"),
  fe %>% filter(grepl("^resid|^comm", sector)) %>% mutate(variable = "Final Energy|Building|Hydrogen"),
  fe %>% filter(sector == "agricultural energy use") %>% mutate(variable = "Final Energy|AFOFI|Hydrogen")
) %>%
  group_by(scenario, year, variable) %>%
  summarise(db_direct = sum(value) * ej_to_ktoe, .groups = "drop") %>%
  complete(scenario, year, variable, fill = list(db_direct = 0))

########## Pipeline result (ktoe) ##########
read_after <- function(f, col) {
  read.csv(f, check.names = FALSE, stringsAsFactors = FALSE) %>%
    filter(Variable %in% unique(direct$variable)) %>%
    select(scenario = Scenario, variable = Variable, matches("^20[2-9][05]$")) %>%
    pivot_longer(-c(scenario, variable), names_to = "year", values_to = col) %>%
    mutate(year = as.numeric(year), !!col := tidyr::replace_na(as.numeric(.data[[col]]), 0))
}
cmp <- direct %>%
  left_join(read_after(file.path(output_dir, "variables_after_unit_conversion.csv"), "kmip"),
            by = c("scenario", "year", "variable"))
if (!is.na(before_csv))
  cmp <- cmp %>% left_join(read_after(before_csv, "kmip_before"), by = c("scenario", "year", "variable"))
var_order <- c("Secondary Energy|Hydrogen", "Secondary Energy|Hydrogen|Import",
               "Secondary Energy|Hydrogen|Domestic", "Secondary Energy|Hydrogen|Domestic|Electricity",
               "Secondary Energy|Hydrogen|Domestic|Gas|w/o CCS", "Secondary Energy|Hydrogen|Domestic|Gas|w/ CCS",
               "Secondary Energy|Hydrogen|Domestic|Biomass",
               "Primary Energy|Electricity|Hydrogen", "Primary Energy|Gas|Hydrogen", "Primary Energy|Biomass|Hydrogen",
               "Final Energy|Hydrogen", "Final Energy|Industry|Hydrogen",
               "Final Energy|Industry|Iron and Steel|Hydrogen", "Final Energy|Industry|Non-Metallic Minerals|Hydrogen",
               "Final Energy|Industry|Chemicals|Hydrogen", "Final Energy|Industry|Other Sector|Hydrogen",
               "Final Energy|Transportation|Hydrogen", "Final Energy|Transportation|Road|Hydrogen",
               "Final Energy|Transportation|Rail|Hydrogen", "Final Energy|Transportation|Ship|Hydrogen",
               "Final Energy|Transportation|Air|Hydrogen", "Final Energy|Building|Hydrogen",
               "Final Energy|AFOFI|Hydrogen")
cmp <- cmp %>%
  mutate(diff_pct = ifelse(db_direct == 0 & kmip == 0, 0, 100 * (kmip - db_direct) / pmax(abs(db_direct), 1e-9)),
         variable = factor(variable, levels = var_order)) %>%
  arrange(scenario, year, variable)

out_csv <- file.path(output_dir, paste0(run_name, "_h2_compare.csv"))
write.csv(cmp, out_csv, row.names = FALSE)
cat("Wrote", out_csv, "\n")
bad <- cmp %>% filter(abs(diff_pct) > 1)
cat(sprintf("Rows off by more than 1%%: %d of %d\n", nrow(bad), nrow(cmp)))
if (nrow(bad) > 0) print(as.data.frame(bad), row.names = FALSE)

########## Figure (one scenario, one year) ##########
# PPT size: 13.33 x 7.5 in, all text 16 pt and black
pal <- c("DB direct" = "#1baf7a", "KMIP output" = "#2a78d6", "Before update" = "#eb6834")
shp <- c("DB direct" = 21, "KMIP output" = 16, "Before update" = 4)
fig <- cmp %>%
  filter(scenario == fig_scen, year == fig_year) %>%
  select(variable, `DB direct` = db_direct, `KMIP output` = kmip, any_of(c(`Before update` = "kmip_before"))) %>%
  pivot_longer(-variable, names_to = "source", values_to = "ktoe") %>%
  filter(ktoe > 0) %>%
  # short labels: SE / PE / FE prefix, the Hydrogen part dropped
  mutate(label = sub("\\|Hydrogen(\\||$)", "\\1", as.character(variable)),
         label = sub("^Secondary Energy", "SE", sub("^Primary Energy", "PE", sub("^Final Energy", "FE", label))),
         label = sub("\\|$", "", label),
         label = factor(label, levels = rev(unique(label[order(variable)]))),
         source = factor(source, levels = names(pal)))

p <- ggplot(fig, aes(ktoe, label, colour = source, shape = source)) +
  geom_point(aes(size = source), stroke = 1.6) +
  scale_colour_manual(values = pal, name = NULL) +
  scale_shape_manual(values = shp, name = NULL) +
  scale_size_manual(values = c("DB direct" = 6, "KMIP output" = 3, "Before update" = 4), name = NULL) +
  scale_x_log10(labels = scales::label_comma(accuracy = 1)) +
  labs(x = sprintf("ktoe/yr (log scale), %s %d", fig_scen, fig_year), y = NULL) +
  theme_minimal(base_size = 16) +
  theme(text = element_text(colour = "black"), axis.text = element_text(colour = "black", size = 16),
        legend.position = "top", legend.text = element_text(size = 16),
        panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = "grey88"))

out_png <- file.path(output_dir, paste0(run_name, "_h2_compare.png"))
ggsave(out_png, p, width = 13.33, height = 7.5, dpi = 150, bg = "white")
cat("Wrote", out_png, "\n")
