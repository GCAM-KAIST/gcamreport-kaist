################################################################################
# Compare KAIST9 (GCAM 9.1) runs with the KMIP2025 GC submission.
#
# Figures (PNG each + one combined PDF), each with a value table below:
#   1a GHG, KMIP template scope (energy + cement process - DAC): GC submitted vs kaist9
#   1b GHG, national gross / net (Kyoto Gases): KMIP25 step2 rerun vs kaist9
#   2  Primary energy by fuel, 3 Electricity generation by source,
#   4  Final energy by sector: GC submitted vs kaist9
#
# kaist9 input, first found is used:
#   1. step2 Korea csv (kaist9_hlm_korea.csv): used as is (b1, a3 already applied)
#   2. raw step1 (kaist9_hlm.csv/.xlsx): here we apply b1 bunker rule
#      (aviation 0.099, shipping 0.039) and a3 renewable primary x2.1
# If a step4 file (KMIP template variables, variables_after_unit_conversion.csv)
# exists, figures 1a/2/3/4 use it with the same definitions as the GC rows.
#
# Usage (from gcamreport-kaist/):
#   Rscript kaist/kmip/tools/compare_kaist9_kmip25.R [kaist9_file] [out_dir] [step4_file]
################################################################################

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(readxl)
  library(ggplot2)
  library(grid)
  library(gridExtra)
})

########## Paths ##########
args <- commandArgs(trailingOnly = TRUE)
repo_dir <- "/home/jiheun/reporting/gcamreport-kaist"
k9_dir   <- "/home/jiheun/reporting/kmip/KAIST9_HLM_output"
k25_dir  <- "/home/jiheun/reporting/kmip/KMIP25_6Scenarios_output"

first_existing <- function(f) { f <- f[file.exists(f)]; if (length(f)) f[1] else NA_character_ }
k9_file <- if (length(args) >= 1) args[1] else
  first_existing(file.path(k9_dir, c("kaist9_hlm_korea.csv", "kaist9_hlm.xlsx")))  # .csv is overwritten by step2
k9_is_step2 <- grepl("_korea\\.csv$", k9_file)
k9_tmpl_file <- if (length(args) >= 3) first_existing(args[3]) else  # "none" = skip step4
  first_existing(file.path(k9_dir, "variables_after_unit_conversion.csv"))
out_dir <- if (length(args) >= 2) args[2] else file.path(k9_dir, "compare_kmip25")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# KMIP2025 submission (MT+GC+MS); found by pattern (Korean file name)
sub_file <- list.files(k25_dir, pattern = "MT\\+GC\\+MS.*\\.xlsx$", full.names = TRUE)[1]
# KMIP25 DB through our current pipeline (step2, Korea)
k25_step2_file <- file.path(k25_dir, "kmip26_all8_korea.csv")

table_years <- c(2020, 2030, 2035, 2040, 2050)
plot_years  <- seq(2020, 2050, 5)
gc_scen     <- c("S0.7_ESM", "S0.8_ESM", "S0.9", "S1", "S1.1")
k9_scen     <- c("high_ref", "high_nz", "medium_ref", "medium_nz", "low_ref", "low_nz")
###########################

########## Constants ##########
EJ_TO_MTOE <- 23.884589   # same factor as unit_table.R (ktoe/1000)
EJ_TO_TWH  <- 277.7777778
GWP_CH4 <- 27.2           # Mt CH4 -> Mt CO2eq (unit_table.R)
GWP_N2O <- 0.273          # kt N2O -> Mt CO2eq (unit_table.R)
###############################

########## Read inputs ##########
source(file.path(repo_dir, "kaist/kmip/modules/00_utils.R"))
source(file.path(repo_dir, "kaist/kmip/modules/b1_bunker_emissions.R"))
source(file.path(repo_dir, "kaist/kmip/modules/a3_nuclear_renewables.R"))

read_iamc <- function(f) {
  d <- if (grepl("\\.xlsx$", f)) read_excel(f) else read_csv(f, show_col_types = FALSE)
  d <- as.data.frame(d)
  # GCAM 9.1 base year is 2021: show it in the 2020 slot
  if ("2021" %in% names(d) && !"2020" %in% names(d)) names(d)[names(d) == "2021"] <- "2020"
  yc <- year_cols(d)
  d[yc] <- lapply(d[yc], function(x) replace_na(as.numeric(x), 0))
  d
}

cat("kaist9 file:", k9_file, if (k9_is_step2) "(step2)" else "(raw step1)", "\n")
k9 <- read_iamc(k9_file) %>% filter(Region == "South Korea")
k9 <- k9[, c("Model", "Scenario", "Region", "Variable", "Unit",
             intersect(year_cols(k9), as.character(2015:2050)))]
k9_missing_scen <- setdiff(k9_scen, unique(k9$Scenario))
if (length(k9_missing_scen) > 0) {
  cat("NOTE: kaist9 scenarios not found:", k9_missing_scen,
      "-> using all scenarios in file\n")
  k9_scen <- unique(k9$Scenario)
}
k9 <- k9 %>% filter(Scenario %in% k9_scen)

# raw step1 only: b1 bunker rule (0.099 / 0.039) and a3 renewable primary scaling
if (!k9_is_step2) {
  k9 <- reallocate_all_bunker_emissions(k9, gases = c("CO2", "N2O", "CH4", "Kyoto Gases"))
  k9 <- scale_renewable_primary(k9)
}

# step4 template variables (KMIP names/units), if present for these scenarios
k9_tmpl <- NULL
if (!is.na(k9_tmpl_file)) {
  k9_tmpl <- read_iamc(k9_tmpl_file) %>% filter(Scenario %in% k9_scen)
  if (nrow(k9_tmpl) == 0) { k9_tmpl <- NULL; cat("NOTE: step4 file has no kaist9 scenarios, ignored\n") }
  else cat("kaist9 step4 file:", k9_tmpl_file, "\n")
}
k9_mode <- if (!is.null(k9_tmpl)) "step4 template" else if (k9_is_step2) "step2" else "raw step1 + b1/a3 here"

k25 <- read_iamc(k25_step2_file) %>% filter(Scenario %in% c("ref", gc_scen))

gc_sub <- read_excel(sub_file, sheet = "data") %>%
  mutate(across(c(Model, Scenario, Variable, Unit), trimws)) %>%
  filter(Model == "GC")
gc_sub <- as.data.frame(gc_sub)
gc_sub[year_cols(gc_sub)] <- lapply(gc_sub[year_cols(gc_sub)], function(x) replace_na(as.numeric(x), 0))
#################################

########## Indicator definitions ##########
# Each item: category -> candidate variable sets (first set with any row found
# is used; a set is summed). Names for gcamreport (IAMC) and KMIP template.
missing_log <- list()

get_var <- function(d, cands, src, fig, cat_name) {
  for (vs in cands) {
    hit <- d %>% filter(Variable %in% vs)
    if (nrow(hit) > 0) {
      return(hit %>%
               pivot_longer(matches("^[0-9]{4}$"), names_to = "year", values_to = "value") %>%
               mutate(year = as.integer(year)) %>%
               group_by(Scenario, year) %>% summarise(value = sum(value), .groups = "drop"))
    }
  }
  missing_log[[length(missing_log) + 1]] <<- tibble(
    source = src, figure = fig, category = cat_name,
    tried = paste(sapply(cands, paste, collapse = " + "), collapse = " | "))
  tibble(Scenario = unique(d$Scenario)) %>% crossing(year = plot_years) %>% mutate(value = 0)
}

# Build one figure's long table: items = list(category = list(cands...)),
# total = candidates for the total ("Other" = total - sum(items)), factor = unit.
build <- function(d, src, fig, items, total = NULL, factor = 1) {
  parts <- bind_rows(lapply(names(items), function(nm)
    get_var(d, items[[nm]], src, fig, nm) %>% mutate(category = nm)))
  if (!is.null(total)) {
    tot <- get_var(d, total, src, fig, "TOTAL")
    other <- tot %>% left_join(parts %>% group_by(Scenario, year) %>%
                                 summarise(s = sum(value), .groups = "drop"),
                               by = c("Scenario", "year")) %>%
      transmute(Scenario, year, value = value - s, category = "Other")
    parts <- bind_rows(parts, other)
  }
  parts %>% mutate(value = value * factor, figure = fig)
}

# --- Figure 1a: KMIP template GHG scope (Mt CO2eq) ---
ghg_scope_iamc <- function(d, src) {
  x <- list(
    co2 = get_var(d, list("Emissions|CO2|Energy"), src, "1a", "CO2 energy"),
    ch4 = get_var(d, list("Emissions|CH4|Energy"), src, "1a", "CH4 energy") %>% mutate(value = value * GWP_CH4),
    n2o = get_var(d, list("Emissions|N2O|Energy"), src, "1a", "N2O energy") %>% mutate(value = value * GWP_N2O),
    # cement only, as the KMIP mapping (b6 steel process row is inside CO2|Energy)
    ip  = get_var(d, list("Emissions|CO2|Industrial Processes|Cement"), src, "1a", "IP cement"),
    dac = get_var(d, list("Carbon Capture|Direct Air Capture"), src, "1a", "DAC") %>% mutate(value = -value))
  bind_rows(x) %>% group_by(Scenario, year) %>% summarise(value = sum(value), .groups = "drop")
}
ghg_scope_gc <- function(d) {
  vars <- c("Emissions|CO2|Energy", "Emissions|CH4|Energy", "Emissions|N2O|Energy",
            "Emissions|GHGs|Non-Energy|Industrial Process")
  # DAC sign differs (submission negative, step4 output positive): subtract |DAC|
  dac <- get_var(d, list("Carbon Sequestration|DAC"), "GC", "1a", "DAC") %>% mutate(value = -abs(value))
  bind_rows(get_var(d, list(vars), "GC", "1a", "energy+IP"), dac) %>%
    group_by(Scenario, year) %>% summarise(value = sum(value), .groups = "drop")
}

# --- Figure 1b: national gross / net (as step6) ---
ghg_national <- function(d, src) {
  kyoto <- get_var(d, list("Emissions|Kyoto Gases"), src, "1b", "Kyoto")
  luc   <- get_var(d, list("Emissions|CO2|AFOLU"), src, "1b", "CO2 AFOLU")
  land  <- get_var(d, list("Emissions|Kyoto Gases|AFOLU|Land"), src, "1b", "Kyoto AFOLU Land")
  kyoto %>% rename(net = value) %>%
    left_join(luc %>% rename(luc = value), by = c("Scenario", "year")) %>%
    left_join(land %>% rename(land = value), by = c("Scenario", "year")) %>%
    transmute(Scenario, year, `Net (incl. LULUCF)` = net,
              `Gross (excl. LULUCF)` = net - luc - land) %>%
    pivot_longer(-c(Scenario, year), names_to = "category", values_to = "value")
}

# --- Figure 2: primary energy by fuel (Mtoe) ---
pe_fuels <- c("Coal", "Oil", "Gas", "Biomass", "Nuclear", "Hydro", "Solar", "Wind", "Geothermal")
pe_items <- setNames(lapply(pe_fuels, function(f) list(paste0("Primary Energy|", f))), pe_fuels)

# --- Figure 3: electricity generation by source (TWh) ---
el_iamc <- list(
  Coal = list("Secondary Energy|Electricity|Coal"),
  Oil = list("Secondary Energy|Electricity|Oil"),
  Gas = list("Secondary Energy|Electricity|Gas"),
  Biomass = list("Secondary Energy|Electricity|Biomass"),
  Nuclear = list("Secondary Energy|Electricity|Nuclear"),
  Hydro = list("Secondary Energy|Electricity|Hydro"),
  Solar = list("Secondary Energy|Electricity|Solar"),
  Wind = list("Secondary Energy|Electricity|Wind"),
  Geothermal = list("Secondary Energy|Electricity|Geothermal"),
  Hydrogen = list("Secondary Energy|Electricity|Hydrogen"))
el_gc <- list(
  Coal = list(paste0("Secondary Energy|Electricity|Coal|", c("w/ CCS", "w/o CCS"))),
  Oil = list(paste0("Secondary Energy|Electricity|Oil|", c("w/ CCS", "w/o CCS"))),
  Gas = list(paste0("Secondary Energy|Electricity|Gas|", c("w/ CCS", "w/o CCS"))),
  Biomass = list(paste0("Secondary Energy|Electricity|Biomass|", c("w/ CCS", "w/o CCS"))),
  Nuclear = list("Secondary Energy|Electricity|Nuclear"),
  Hydro = list("Secondary Energy|Electricity|Hydro"),
  Solar = list(c("Secondary Energy|Electricity|Solar|PV", "Secondary Energy|Electricity|Solar|CSP")),
  Wind = list(c("Secondary Energy|Electricity|Wind|Onshore", "Secondary Energy|Electricity|Wind|Offshore")),
  Hydrogen = list("Secondary Energy|Electricity|Hydrogen"))

# --- Figure 4: final energy by sector (Mtoe) ---
fe_iamc <- list(
  Industry = list("Final Energy|Industry"),
  Transportation = list("Final Energy|Transportation"),
  Buildings = list("Final Energy|Residential and Commercial", "Final Energy|Buildings",
                   c("Final Energy|Residential", "Final Energy|Commercial")),
  AFOFI = list("Final Energy|Agriculture"),
  `Non-energy use` = list("Final Energy|Non-Energy Use"),
  `Intl. bunkers` = list("Final Energy|Bunkers"))
fe_gc <- list(
  Industry = list("Final Energy|Industry"),
  Transportation = list("Final Energy|Transportation"),
  Buildings = list("Final Energy|Building"),
  AFOFI = list("Final Energy|AFOFI"))
###########################################

########## Compute ##########
lab_gc  <- function(s) paste0("KMIP25 GC ", s)
lab_k25 <- function(s) paste0("KMIP25 ", s, " (rerun)")
lab_k9  <- function(s) paste0("K9 ", s)

tag <- function(df, src, labf) df %>% mutate(source = src, series = labf(Scenario))

fig1a <- bind_rows(
  ghg_scope_gc(gc_sub) %>% filter(Scenario %in% gc_scen) %>% tag("KMIP25 GC submitted", lab_gc),
  (if (!is.null(k9_tmpl)) ghg_scope_gc(k9_tmpl) else ghg_scope_iamc(k9, "kaist9")) %>%
    tag("kaist9", lab_k9)) %>%
  mutate(category = "Energy + IP (KMIP scope)")

fig1b <- bind_rows(
  ghg_national(k25, "KMIP25 step2") %>% tag("KMIP25 step2 rerun", lab_k25),
  ghg_national(k9, "kaist9") %>% tag("kaist9", lab_k9))

fig2 <- bind_rows(
  build(gc_sub %>% filter(Scenario %in% gc_scen), "GC", "2", pe_items, list("Primary Energy"), 1 / 1000) %>%
    tag("KMIP25 GC submitted", lab_gc),
  (if (!is.null(k9_tmpl)) build(k9_tmpl, "kaist9 step4", "2", pe_items, list("Primary Energy"), 1 / 1000)
   else build(k9, "kaist9", "2", pe_items, list("Primary Energy"), EJ_TO_MTOE)) %>% tag("kaist9", lab_k9))

fig3 <- bind_rows(
  build(gc_sub %>% filter(Scenario %in% gc_scen), "GC", "3", el_gc, list("Secondary Energy|Electricity"), 1 / 1000) %>%
    tag("KMIP25 GC submitted", lab_gc),
  (if (!is.null(k9_tmpl)) build(k9_tmpl, "kaist9 step4", "3", el_gc, list("Secondary Energy|Electricity"), 1 / 1000)
   else build(k9, "kaist9", "3", el_iamc, list("Secondary Energy|Electricity"), EJ_TO_TWH)) %>% tag("kaist9", lab_k9))

fig4 <- bind_rows(
  build(gc_sub %>% filter(Scenario %in% gc_scen), "GC", "4", fe_gc, list("Final Energy"), 1 / 1000) %>%
    tag("KMIP25 GC submitted", lab_gc),
  # gcamreport names here even with step4: 9.1 has Non-Energy Use and Bunkers
  # as own rows, which the template maps to nothing (they fall into Other)
  build(k9, "kaist9", "4", fe_iamc, list("Final Energy"), EJ_TO_MTOE) %>% tag("kaist9", lab_k9))

missing_df <- bind_rows(missing_log) %>% distinct()
if (nrow(missing_df) > 0) {
  cat("\n=== Variables not found (counted as 0) ===\n")
  print(as.data.frame(missing_df), right = FALSE)
  write_csv(missing_df, file.path(out_dir, "missing_variables.csv"))
}
#############################

########## Series styling ##########
# kaist9: color by family (high/medium/low), nz solid, ref dashed.
# KMIP25: gray shades, solid, thinner.
series_levels <- c(lab_gc(gc_scen), lab_k25(c("ref", gc_scen)), lab_k9(k9_scen))
fam_col <- c(high = "#d03b2f", medium = "#2a78d6", low = "#1b8a5a")
fallback_col <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948")
k9_col <- mapply(function(s, i) {
  f <- sub("_.*", "", s); if (f %in% names(fam_col)) fam_col[[f]] else fallback_col[(i - 1) %% 8 + 1]
}, k9_scen, seq_along(k9_scen))
gray_shades <- c("#222222", "#555555", "#777777", "#999999", "#bbbbbb")
series_col <- c(setNames(gray_shades, lab_gc(gc_scen)),
                setNames(c("#000000", gray_shades), lab_k25(c("ref", gc_scen))),
                setNames(k9_col, lab_k9(k9_scen)))
series_lty <- c(setNames(rep("solid", 5), lab_gc(gc_scen)),
                setNames(c("dashed", rep("solid", 5)), lab_k25(c("ref", gc_scen))),
                setNames(ifelse(grepl("ref", k9_scen), "dashed", "solid"), lab_k9(k9_scen)))
series_lwd <- c(setNames(rep(0.5, 11), c(lab_gc(gc_scen), lab_k25(c("ref", gc_scen)))),
                setNames(rep(0.9, length(k9_scen)), lab_k9(k9_scen)))

cat_fill <- c(Coal = "#3d3d3d", Oil = "#8c564b", Gas = "#7fb3e6", Biomass = "#5aa05a",
              Nuclear = "#9467bd", Hydro = "#1f5fa8", Solar = "#f2c12e", Wind = "#5cc8c0",
              Geothermal = "#d98c5f", Hydrogen = "#e377c2", Other = "#c8c8c8",
              Industry = "#4a6fa5", Transportation = "#e07b39", Buildings = "#6aa84f",
              AFOFI = "#b39b5c", `Non-energy use` = "#8fb8d8", `Intl. bunkers` = "#9e9e9e")

plot_family <- if (.Platform$OS.type == "windows") "Arial" else "Liberation Sans"
base_theme <- theme_bw(base_size = 11, base_family = plot_family) +
  theme(panel.grid.minor = element_blank(),
        plot.caption = element_text(size = 8, hjust = 0),
        legend.text = element_text(size = 9))
####################################

########## Table + page helpers ##########
# Wide value table: rows = series, cols = table_years. KMIP25 and K9 rows go
# in two tables side by side to keep the page short. Built inside the open
# device so text widths match the output font.
make_table <- function(d, digits = 0) {
  one <- function(dd) {
    w <- dd %>% filter(year %in% table_years) %>% arrange(series, year) %>%
      mutate(value = formatC(value, format = "f", digits = digits, big.mark = ",")) %>%
      select(series, year, value) %>%
      pivot_wider(names_from = year, values_from = value) %>%
      rename(Scenario = series)
    names(w)[names(w) == "2020"] <- "2020/21"
    tableGrob(w, rows = NULL,
              theme = ttheme_minimal(base_size = 8.5, base_family = plot_family,
                                     padding = unit(c(5, 2.2), "mm"),
                                     core = list(fg_params = list(hjust = 1, x = 0.95)),
                                     colhead = list(fg_params = list(fontface = "bold"))))
  }
  is_k9 <- grepl("^K9 ", d$series)
  arrangeGrob(one(d[!is_k9, ]), one(d[is_k9, ]), ncol = 2)
}

pages <- list()
draw_page <- function(pg) {
  g <- arrangeGrob(ggplotGrob(pg$p), pg$tbl(), ncol = 1,
                   heights = unit(c(1 - pg$tbl_height, pg$tbl_height), "npc"))
  grid.newpage(); grid.draw(g)
}
save_page <- function(name, p, tbl_data, tbl_height = 0.24, width = 13.333, height = 7.5) {
  pg <- list(p = p, tbl = function() make_table(tbl_data), tbl_height = tbl_height)
  f <- file.path(out_dir, paste0(name, ".png"))
  png(f, width = width, height = height, units = "in", res = 120, bg = "white")
  draw_page(pg); invisible(dev.off())
  pages[[name]] <<- pg
  cat("Saved", f, "\n")
}

order_series <- function(d) d %>%
  filter(series %in% series_levels) %>%
  mutate(series = factor(series, levels = intersect(series_levels, unique(series))))

line_plot <- function(d, title, ylab, caption, facet = FALSE) {
  d <- order_series(d) %>% filter(year %in% plot_years)
  ggplot(d, aes(year, value, color = series, linetype = series, linewidth = series)) +
    geom_hline(yintercept = 0, color = "gray60", linewidth = 0.3) +
    geom_line() +
    {if (facet) facet_wrap(~category)} +
    scale_color_manual(values = series_col, name = NULL) +
    scale_linetype_manual(values = series_lty, name = NULL) +
    scale_linewidth_manual(values = series_lwd, name = NULL) +
    scale_x_continuous(breaks = plot_years) +
    labs(title = title, x = NULL, y = ylab, caption = caption) +
    base_theme
}

bar_plot <- function(d, title, ylab, caption) {
  d <- order_series(d) %>% filter(year %in% table_years)
  cats <- intersect(names(cat_fill), unique(d$category))
  d <- d %>% mutate(category = factor(category, levels = rev(cats)))
  ggplot(d, aes(series, value, fill = category)) +
    geom_col(width = 0.8) +
    geom_hline(yintercept = 0, color = "gray40", linewidth = 0.3) +
    facet_wrap(~year, nrow = 1) +
    scale_fill_manual(values = cat_fill, breaks = cats, name = NULL) +
    labs(title = title, x = NULL, y = ylab, caption = caption) +
    base_theme +
    theme(axis.text.x = element_text(angle = 60, hjust = 1, size = 7.5),
          strip.background = element_rect(fill = "white"))
}

totals <- function(d) d %>% group_by(series, year) %>% summarise(value = sum(value), .groups = "drop")
##########################################

########## Figures ##########
src_note <- paste0("KMIP25 GC = KMIP2025 submission (GC rows of the MT+GC+MS workbook). ",
                   "K9 = kaist9 GCAM 9.1 runs (",
                   if (!is.null(k9_tmpl)) basename(k9_tmpl_file) else basename(k9_file), "; ", k9_mode, "). ",
                   "K9 base year 2021 is shown at 2020 (column 2020/21), no interpolation.")
bunker_note <- paste0("Bunkers: aviation and shipping are pooled and only the domestic share is kept ",
                      "(K9: aviation 0.099 / shipping 0.039, GIR 2025; KMIP25 GC used the older 0.093 / 0.032).")

cap1a <- paste(src_note, bunker_note,
               "Scope = KMIP template: CO2 + CH4 + N2O from energy, cement process CO2, minus DAC (no LULUCF, no other non-energy GHG).",
               "KMIP25 GC 2020 values are inventory values entered in the template, not GCAM output.", sep = "\n")
save_page("fig1a_ghg_kmip_scope",
          line_plot(fig1a, "South Korea GHG, KMIP template scope (energy + IP - DAC)", "Mt CO2eq/yr", cap1a),
          order_series(fig1a), tbl_height = 0.24)

cap1b <- paste(paste0("KMIP25 (rerun) = KMIP25 DB through the current pipeline (step2 Korea csv, ",
                      basename(k25_step2_file), "); the GC submission has no national total."),
               bunker_note,
               "Net = Emissions|Kyoto Gases (incl. LULUCF). Gross = Net - CO2 AFOLU - Kyoto AFOLU|Land (as step6).",
               "KMIP25 rerun step2 csv was made before the bunker-share update, so it still uses 0.093 / 0.032.", sep = "\n")
save_page("fig1b_ghg_national_gross_net",
          line_plot(fig1b, "South Korea GHG emissions, national total", "Mt CO2eq/yr", cap1b, facet = TRUE),
          order_series(fig1b) %>% arrange(category, series) %>%
            mutate(series = paste0(series, if_else(grepl("^Net", category), " | net", " | gross")),
                   series = factor(series, levels = unique(series))),
          tbl_height = 0.36)

cap2 <- paste(src_note,
              "Nuclear / hydro / solar / wind / geothermal primary energy x2.1 (KMIP convention, a3 module) for both sources.",
              "Other = total - listed fuels (e.g. hydrogen import, secondary energy trade). Table = total primary energy (Mtoe).", sep = "\n")
save_page("fig2_primary_energy",
          bar_plot(fig2, "Primary energy by fuel", "Mtoe/yr", cap2),
          order_series(totals(fig2)), tbl_height = 0.24)

cap3 <- paste(src_note,
              "Other = total - listed sources. Table = total electricity generation (TWh).", sep = "\n")
save_page("fig3_electricity_generation",
          bar_plot(fig3, "Electricity generation by source", "TWh/yr", cap3),
          order_series(totals(fig3)), tbl_height = 0.24)

cap4 <- paste(src_note,
              paste0("K9 bars use the step2 gcamreport rows (", basename(k9_file), "): GCAM 9.1 reports Non-energy use (feedstocks) and Intl. bunkers as own rows;\n",
                     "KMIP25 GC has no such split (feedstocks sit inside Industry). Other = total - listed sectors."),
              "Table = total final energy (Mtoe).", sep = "\n")
save_page("fig4_final_energy_by_sector",
          bar_plot(fig4, "Final energy by sector", "Mtoe/yr", cap4),
          order_series(totals(fig4)), tbl_height = 0.24)
#############################

########## Combined PDF + data ##########
pdf_file <- file.path(out_dir, "compare_kaist9_kmip25.pdf")
cairo_pdf(pdf_file, width = 13.333, height = 7.5, onefile = TRUE, family = plot_family)
for (pg in pages) draw_page(pg)
invisible(dev.off())
cat("Saved", pdf_file, "\n")

all_data <- bind_rows(
  fig1a %>% mutate(figure = "1a GHG KMIP scope", unit = "Mt CO2eq/yr"),
  fig1b %>% mutate(figure = "1b GHG national", unit = "Mt CO2eq/yr"),
  fig2 %>% mutate(figure = "2 Primary energy", unit = "Mtoe/yr"),
  fig3 %>% mutate(figure = "3 Electricity generation", unit = "TWh/yr"),
  fig4 %>% mutate(figure = "4 Final energy", unit = "Mtoe/yr")) %>%
  filter(year %in% plot_years) %>%
  select(figure, source, series, category, unit, year, value) %>%
  pivot_wider(names_from = year, values_from = value)
write_csv(all_data, file.path(out_dir, "compare_kaist9_kmip25_data.csv"))
cat("Saved", file.path(out_dir, "compare_kaist9_kmip25_data.csv"), "\n")
#########################################
