################################################################################
# Step 5: Report
#
#   1. National GHG pathway figure from the step2 Korea csv: Mt CO2eq/yr, one
#      line per scenario, panels Gross (excl. LULUCF) and Net (incl. LULUCF).
#      Emissions|Kyoto Gases excludes international bunkers after the b1
#      reallocation (years >= 2020; earlier years keep raw GCAM values).
#   2. When the settings name a reference run (compare_a_file): the comparison
#      report, kaist/kmip/step5_report.qmd rendered with quarto. Part 1 puts all
#      scenarios of this run next to the reference (GHG in the KMIP scope,
#      national gross/net GHG, primary energy, electricity, final energy by
#      sector); Part 2 is one scenario pair, variable by variable.
#
# INPUT:  {output_dir}/{run_name}_korea.csv (step2); for the comparison also
#         variables_after_unit_conversion.csv (step3) and the compare_* settings
#         (see kaist/kmip/config/kaist9_low26.R)
# OUTPUT: {output_dir}/{run_name}_ghg_pathway.png / .csv
#         {output_dir}/compare/{run_name}_compare.pdf, one png + csv per section
# Quarto: `quarto` on PATH, or set QUARTO_BIN (RStudio Server ships one under
#         /usr/lib/rstudio-server/bin/quarto/bin/quarto).
################################################################################

########## Load configuration ##########
source(file.path(getwd(), "kaist/core/config.R"))
########################################

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})

########## 1. GHG pathway figure ##########
# Fixed scenario -> color assignment (colorblind-validated palette, fixed
# order). A scenario keeps its color no matter which subset is plotted.
scenario_order <- c("ref", "S1", "S1.1", "S0.9",
                    "S0.7_ESM", "S0.8_ESM", "S08_61", "S1_53")
palette_hex <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100",
                 "#e87ba4", "#008300", "#4a3aa7", "#e34948")
scenario_colors <- setNames(palette_hex, scenario_order)

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

# Keep only the panels asked for in the settings (plot_measures: "Gross", "Net").
keep <- get0("plot_measures", ifnotfound = c("Gross", "Net"))
ghg <- ghg %>% filter(sub(" .*", "", measure) %in% keep) %>% droplevels()

# unknown scenario names get the unused palette slots, in order
scen_known <- intersect(scenario_order, unique(ghg$Scenario))
scen_extra <- setdiff(unique(ghg$Scenario), scenario_order)
if (length(scen_extra) > 0) {
  free_hex <- setdiff(palette_hex, scenario_colors[scen_known])
  scenario_colors <- c(scenario_colors[scen_known],
                       setNames(free_hex[seq_along(scen_extra)], scen_extra))
}
ghg$Scenario <- factor(ghg$Scenario, levels = c(scen_known, scen_extra))

# Line-end labels only for a few scenarios; with many they overlap, so the
# legend alone carries identity.
show_end_labels <- length(unique(ghg$Scenario)) <= 3 &&
  max(nchar(as.character(unique(ghg$Scenario)))) <= 8

# Plain style on purpose: white background, standard theme_bw look.
# Same Arial-metric font on both OSes (server has Liberation Sans installed).
plot_family <- if (.Platform$OS.type == "windows") "Arial" else "Liberation Sans"

plot_start <- get0("plot_start_year", ifnotfound = start_year)
ghg <- ghg %>% filter(year >= plot_start)

p <- ggplot(ghg, aes(year, value, color = Scenario)) +
  geom_hline(yintercept = 0, color = "gray60", linewidth = 0.3) +
  geom_line(linewidth = 0.8) +
  {if (nlevels(ghg$measure) > 1) facet_wrap(~measure)} +
  scale_color_manual(values = scenario_colors) +
  scale_x_continuous(limits = c(plot_start, final_year + ifelse(show_end_labels, 5, 1)),
                     breaks = seq(plot_start, final_year, 5)) +
  scale_y_continuous(breaks = scales::breaks_width(100)) +
  labs(title = if (nlevels(ghg$measure) == 1) paste("South Korea GHG Emissions,", levels(ghg$measure)) else "South Korea GHG Emissions",
       subtitle = get0("plot_subtitle", ifnotfound = NULL),
       x = NULL, y = "Mt CO2eq/yr", color = NULL) +
  theme_bw(base_size = 13, base_family = plot_family) +
  theme(panel.grid.minor = element_blank(),
        legend.position = "right",
        axis.text = element_text(size = 11),
        legend.text = element_text(size = 11),
        plot.subtitle = element_text(size = 12),
        plot.caption = element_text(size = 9, hjust = 0))

if (show_end_labels) {
  end_labels <- ghg %>% group_by(Scenario, measure) %>% filter(year == max(year))
  p <- p + geom_text(data = end_labels, aes(label = Scenario),
                     hjust = -0.15, size = 3.1, family = plot_family,
                     show.legend = FALSE)
}

# Optional points on the Net panel (from the settings): statutory targets and
# the cap values written in the GCAM XML. Their shapes get their own legend.
net_panel <- function(d, kind) d %>%
  filter(Scenario %in% levels(ghg$Scenario)) %>%
  mutate(Scenario = factor(Scenario, levels = levels(ghg$Scenario)),
         measure = factor("Net (incl. LULUCF)", levels = levels(ghg$measure)),
         kind = kind)
pts <- bind_rows(
  if (!is.null(get0("pathway_targets", ifnotfound = NULL)))
    net_panel(pathway_targets, "statutory target (bunkers excluded)"),
  if (!is.null(get0("pathway_caps", ifnotfound = NULL)))
    net_panel(pathway_caps, "cap in GCAM XML (target + bunkers)"))
if (nrow(pts) > 0 && "Net (incl. LULUCF)" %in% levels(ghg$measure)) {
  shapes <- c(16, 4)[seq_along(unique(pts$kind))]
  p <- p + geom_point(data = pts, aes(year, value, color = Scenario, shape = kind),
                      size = 1.8, stroke = 0.7) +
    scale_shape_manual(values = setNames(shapes, unique(pts$kind)), name = NULL) +
    guides(color = guide_legend(order = 1), shape = guide_legend(order = 2)) +
    theme(legend.position = "inside", legend.position.inside = c(0.98, 0.98),
          legend.justification = c(1, 1), legend.box = "vertical",
          legend.box.just = "left", legend.spacing.y = unit(0, "pt"),
          legend.key.height = unit(16, "pt"), legend.margin = margin(2, 6, 2, 6),
          legend.background = element_rect(fill = "white", color = "gray70", linewidth = 0.3),
          legend.box.background = element_blank())
}
if (!is.null(get0("plot_subtitle", ifnotfound = NULL))) {
  p <- p + labs(caption = paste0(
    "Cap on all 23 GHGs in one South Korea market (MtCO2eq, GWP AR5).\n",
    "pa = CO2_LUC price-adjust (share of the carbon price that land receives)\n",
    "da = CO2_LUC demand-adjust (3.667 = land-use CO2 counted in the cap); cap = 2050 constraint, MtCO2eq"))
}

png_file <- file.path(output_dir, paste0(run_name, "_ghg_pathway.png"))
ggsave(png_file, p, width = if (nlevels(ghg$measure) > 1) 10 else 7,
       height = 4.6, dpi = 150, bg = "white")
series_file <- file.path(output_dir, paste0(run_name, "_ghg_pathway.csv"))
write_csv(ghg %>% arrange(measure, Scenario, year), series_file)
cat("Figure:", png_file, "\nSeries:", series_file, "\n")
###########################################

########## 2. Comparison report ##########
if (!exists("compare_a_file")) {
  cat("No compare_a_file in the settings: comparison report skipped.\n\n=== Step 5 Complete ===\n")
  quit(save = "no")
}
if (!exists("compare_pair")) stop("step5: compare_a_file is set but compare_pair (c(a = ..., b = ...)) is missing")

# File names with Korean letters may be stored in NFD form: match NFC-normalized
resolve_nfc <- function(f) {
  if (file.exists(f)) return(f)
  cand <- list.files(dirname(f), full.names = TRUE)
  hit <- cand[stringi::stri_trans_nfc(basename(cand)) == stringi::stri_trans_nfc(basename(f))]
  if (length(hit) > 0) hit[1] else f
}
compare_a_file <- resolve_nfc(compare_a_file)

out_dir    <- file.path(output_dir, "compare")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
b_template <- file.path(output_dir, "variables_after_unit_conversion.csv")
for (f in c(compare_a_file, b_template, korea_csv))
  if (!file.exists(f)) stop("step5: missing input ", f)

params <- list(
  a_file        = compare_a_file,
  a_model       = get0("compare_a_model", ifnotfound = "GC"),
  a_label       = get0("compare_a_label", ifnotfound = "Reference"),
  a_scenarios   = as.list(get0("compare_a_scenarios", ifnotfound = character(0))),
  b_label       = get0("compare_b_label", ifnotfound = run_name),
  b_template    = b_template,
  b_korea       = korea_csv,
  b_scenarios   = as.list(get0("compare_b_scenarios", ifnotfound = scenarios)),
  pair_a        = unname(compare_pair[["a"]]),
  pair_b        = unname(compare_pair[["b"]]),
  ref_korea_csv = get0("compare_ref_step2_csv", ifnotfound = ""),
  pathway_png   = png_file,
  out_dir       = out_dir,
  save_png      = TRUE
)
yml <- file.path(out_dir, "params.yml")
# write TRUE/FALSE as true/false (yaml's default "yes"/"no" reaches quarto as text)
yaml::write_yaml(params, yml, handlers = list(logical = function(x) {
  r <- ifelse(x, "true", "false"); class(r) <- "verbatim"; r }))

# quarto binary
qb <- Sys.getenv("QUARTO_BIN")
if (qb == "") qb <- unname(Sys.which("quarto"))
if (qb == "" && requireNamespace("quarto", quietly = TRUE)) qb <- quarto::quarto_path()
if (qb == "" && file.exists("/usr/lib/rstudio-server/bin/quarto/bin/quarto"))
  qb <- "/usr/lib/rstudio-server/bin/quarto/bin/quarto"
if (qb == "" || is.na(qb)) stop("step5: quarto not found; set QUARTO_BIN")

qmd    <- file.path(getwd(), "kaist/kmip/step5_report.qmd")
pdf_nm <- paste0(run_name, "_compare.pdf")
cat("Rendering", basename(qmd), "->", file.path(out_dir, pdf_nm), "\n")
st <- system2(qb, c("render", shQuote(qmd), "--to", "pdf", "--execute-params", shQuote(yml),
                    "--output", shQuote(pdf_nm)))
if (st != 0) stop("step5: quarto render failed (exit ", st, ")")
# quarto writes --output relative to the working directory (older versions: next to the qmd)
made <- c(file.path(getwd(), pdf_nm), file.path(dirname(qmd), pdf_nm))
made <- made[file.exists(made)]
if (length(made) == 0) stop("step5: rendered pdf not found")
file.rename(made[1], file.path(out_dir, pdf_nm))

cat("\n=== Step 5 Complete ===\nReport:", file.path(out_dir, pdf_nm), "\nSections (png, csv):", out_dir, "\n")
##########################################
