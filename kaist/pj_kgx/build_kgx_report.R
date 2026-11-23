################################################################################
# pj_kgx: K-ETS rows for the step1 report of the K-GX fund runs.
#
# PURPOSE:
#   The K-GX runs price South Korea through K-ETS markets that gcamreport does
#   not know (<region>CO2_KETS and one linked market per class), so step1 reports
#   Price|Carbon = 0 and Revenue|Government = 0 for the region. This script keeps
#   every step1 row as it is and adds the rows that describe the K-ETS:
#
#     Price|Carbon|K-ETS                        allowance price (face value)
#     Price|Carbon|K-ETS|<class>                price the class pays = face x paid share
#     Allocation|K-ETS|Paid Share|<class>       share of its allocation the class pays for (%)
#     Allocation|K-ETS|Free Share|<class>       100 - paid share (%)
#     Emissions|CO2|K-ETS[|<class>]             CO2 of the covered technologies
#     Revenue|Government|K-ETS[|<class>]        class price x covered CO2
#     Revenue|Government|<sector>               the same by the sectors of gcamreport's Emissions|CO2 tree
#                                               (Revenue|Government|Energy|Supply|Electricity, ...)
#     Price|Carbon|<sector>                     revenue / Emissions|CO2|<sector>: the average price paid
#                                               per tonne of the sector's CO2 (covered and not covered)
#
#   Classes: kaist/pj_kgx/data/kgx_classes.csv. Units as gcamreport: USD_2010/t CO2,
#   billion USD_2010/yr, Mt CO2/yr. Sectors: gcamreport's co2_tech_map (KAIST-patched).
#
# INPUTS (from step1 with the same settings file):
#   {output_dir}/{run_name}.xlsx                 step1 report
#   {output_dir}/{run_name}_project_*.dat        rgcam project with "CO2 prices" and the
#                                                pj_kgx query "K-ETS covered CO2 by tech"
# OUTPUTS:
#   {output_dir}/{run_name}_kgx.xlsx             sheet "data": the step1 rows unchanged, then the
#                                                added rows; sheet "kgx_variables": what each added
#                                                variable is; sheet "checks"
#   {output_dir}/{run_name}_kgx.csv              sheet "data" as csv
#
# USAGE (repo root):
#   KAIST_CONFIG=kaist/pj_kgx/config/kgx_fund_ssp2.R Rscript kaist/pj_kgx/build_kgx_report.R
################################################################################

source(file.path(getwd(), "kaist/core/config.R"))
source(file.path(getwd(), "kaist/kmip/modules/00_utils.R"))     # load_gcam_rda()
suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(rgcam) })

COVERED_QUERY <- "K-ETS covered CO2 by tech"
PRICE_QUERY   <- "CO2 prices"
U_PRICE <- "USD_2010/t CO2"
U_REV   <- "billion USD_2010/yr"
U_EMIS  <- "Mt CO2/yr"
U_SHARE <- "%"

# ---- inputs ------------------------------------------------------------------
report_file <- file.path(output_dir, paste0(run_name, ".xlsx"))
if (!file.exists(report_file)) stop("step1 report not found: ", report_file, " - run step1 with this settings file first")
dats <- list.files(output_dir, pattern = paste0("^", run_name, "_project.*\\.dat$"), full.names = TRUE)
if (length(dats) == 0) stop("no step1 project (", run_name, "_project*.dat) in ", output_dir)
dat_file <- dats[which.max(file.mtime(dats))]
cat("report :", report_file, "\nproject:", dat_file, "\n")

report <- readxl::read_excel(report_file)
year_cols <- names(report)[grepl("^[0-9]{4}$", names(report))]
key_cols  <- setdiff(names(report), year_cols)
model     <- unique(report$Model)[1]

convert <- load_gcam_rda("convert")
usd_per_tc_to_usd2010_per_tco2 <- convert[["conv_90USD_10USD"]] / convert[["conv_C_CO2"]]
million_usd1990_to_billion_usd2010 <- convert[["conv_90USD_10USD"]] / 1000
tech_map <- load_gcam_rda("co2_tech_map")
classes  <- read_kgx_classes(kgx_classes_file)

prj <- rgcam::loadProject(dat_file)
for (q in c(PRICE_QUERY, COVERED_QUERY))
  if (!q %in% rgcam::listQueries(prj)) stop("query '", q, "' not in ", dat_file, " (step1 adds it through project_queries)")

# ---- prices: face market and class markets of the region ---------------------
face_name <- paste0(kgx_region, kgx_face_market)
prices <- rgcam::getQuery(prj, PRICE_QUERY) %>%
  filter(startsWith(market, face_name), Units == "1990$/tC") %>%
  mutate(suffix = substring(market, nchar(face_name) + 1))
unknown <- setdiff(unique(prices$suffix), c("", classes$suffix))
if (length(unknown)) stop("K-ETS class markets not in ", kgx_classes_file, ": ", paste0(face_name, unknown, collapse = ", "))
face <- prices %>% filter(suffix == "") %>% select(scenario, year, face = value)
if (nrow(face) == 0) stop("no market ", face_name, " in the project: not a K-GX fund database?")
class_price <- prices %>%
  filter(suffix != "") %>%
  inner_join(classes, by = "suffix") %>%
  left_join(face, by = c("scenario", "year")) %>%
  mutate(paid = ifelse(face > 0, value / face, NA_real_)) %>%
  select(scenario, year, class, price = value, paid)

# ---- covered CO2 by technology -> class and gcamreport's emissions tree ---------
covered <- rgcam::getQuery(prj, COVERED_QUERY) %>%
  filter(region == kgx_region) %>%
  mutate(suffix = sub("^CO2_KETS", "", ghg)) %>%
  inner_join(classes %>% select(suffix, class), by = "suffix")
if (nrow(covered) == 0) stop("query '", COVERED_QUERY, "' has no rows for ", kgx_region)
covered <- covered %>%
  left_join(class_price %>% select(scenario, year, class, price), by = c("scenario", "year", "class")) %>%
  mutate(price = coalesce(price, 0),
         MtCO2 = value * convert[["conv_C_CO2"]],
         rev = price * value * million_usd1990_to_billion_usd2010)        # billion USD_2010

# sectors: the variables of co2_tech_map that the step1 report holds for the region
region_vars <- unique(report$Variable[report$Region == kgx_region])
tree <- tech_map %>%
  filter(grepl("^Emissions\\|CO2\\|", var), var %in% region_vars) %>%
  distinct(sector, subsector, technology, var)
techs <- distinct(covered, sector, subsector, technology)
mapped <- techs %>% inner_join(tree, by = c("sector", "subsector", "technology"), relationship = "many-to-many")
missing <- anti_join(techs, mapped, by = c("sector", "subsector", "technology"))
if (nrow(missing)) {
  stop("covered technologies without a row in co2_tech_map: ",
       paste(unique(paste(missing$sector, missing$subsector, missing$technology, sep = " / ")), collapse = "; "))
}

# ---- the added rows, long ----------------------------------------------------
long_rows <- function(d, variable, unit) {
  d %>% transmute(Model = model, Scenario = scenario, Region = kgx_region, Variable = variable, Unit = unit,
                  year = as.character(year), value)
}
by_class <- covered %>% group_by(scenario, year, class) %>% summarise(MtCO2 = sum(MtCO2), rev = sum(rev), .groups = "drop")
by_sector <- covered %>%
  inner_join(mapped, by = c("sector", "subsector", "technology"), relationship = "many-to-many") %>%
  group_by(scenario, year, var) %>% summarise(rev = sum(rev), .groups = "drop") %>%
  mutate(sector_var = sub("^Emissions\\|CO2\\|", "", var))
sector_emis <- report %>%
  filter(Region == kgx_region, Variable %in% unique(by_sector$var)) %>%
  pivot_longer(all_of(year_cols), names_to = "year", values_to = "emis") %>%
  transmute(scenario = Scenario, year = as.numeric(year), var = Variable, emis)

added <- bind_rows(
  long_rows(face %>% mutate(value = face * usd_per_tc_to_usd2010_per_tco2), "Price|Carbon|K-ETS", U_PRICE),
  bind_rows(lapply(classes$class, function(cl) {
    cp <- class_price %>% filter(class == cl)
    bind_rows(
      long_rows(cp %>% mutate(value = price * usd_per_tc_to_usd2010_per_tco2), paste0("Price|Carbon|K-ETS|", cl), U_PRICE),
      long_rows(cp %>% filter(!is.na(paid)) %>% mutate(value = 100 * paid), paste0("Allocation|K-ETS|Paid Share|", cl), U_SHARE),
      long_rows(cp %>% filter(!is.na(paid)) %>% mutate(value = 100 * (1 - paid)), paste0("Allocation|K-ETS|Free Share|", cl), U_SHARE),
      long_rows(by_class %>% filter(class == cl) %>% mutate(value = MtCO2), paste0("Emissions|CO2|K-ETS|", cl), U_EMIS),
      long_rows(by_class %>% filter(class == cl) %>% mutate(value = rev), paste0("Revenue|Government|K-ETS|", cl), U_REV))
  })),
  long_rows(by_class %>% group_by(scenario, year) %>% summarise(value = sum(MtCO2), .groups = "drop"), "Emissions|CO2|K-ETS", U_EMIS),
  long_rows(by_class %>% group_by(scenario, year) %>% summarise(value = sum(rev), .groups = "drop"), "Revenue|Government|K-ETS", U_REV),
  bind_rows(lapply(split(by_sector, by_sector$sector_var), function(s) {
    v <- s$sector_var[1]
    p <- s %>% inner_join(sector_emis, by = c("scenario", "year", "var")) %>%
      mutate(value = ifelse(emis > 0, rev / emis * 1000, NA_real_)) %>% filter(!is.na(value))   # billion USD / Mt = 1000 USD/t
    bind_rows(long_rows(s %>% mutate(value = rev), paste0("Revenue|Government|", v), U_REV),
              long_rows(p, paste0("Price|Carbon|", v), U_PRICE))
  }))
) %>%
  filter(year %in% year_cols)

added_wide <- added %>%
  pivot_wider(names_from = year, values_from = value) %>%
  select(all_of(key_cols), any_of(year_cols))
for (y in setdiff(year_cols, names(added_wide))) added_wide[[y]] <- NA_real_
added_wide <- added_wide[, names(report)]
clash <- intersect(paste(added_wide$Scenario, added_wide$Region, added_wide$Variable),
                   paste(report$Scenario, report$Region, report$Variable))
if (length(clash)) stop("added rows would duplicate step1 rows: ", paste(head(clash, 5), collapse = "; "))
added_wide <- added_wide %>% arrange(Scenario, Variable)

# ---- optional: the region's headline rows ------------------------------------
out <- report
if (isTRUE(kgx_fill_headline)) {
  for (pair in list(c("Price|Carbon", "Price|Carbon|K-ETS"), c("Revenue|Government", "Revenue|Government|K-ETS"))) {
    for (s in unique(added_wide$Scenario)) {
      src <- added_wide[added_wide$Scenario == s & added_wide$Variable == pair[2], year_cols]
      hit <- out$Scenario == s & out$Region == kgx_region & out$Variable == pair[1]
      if (sum(hit) == 1 && nrow(src) == 1) out[hit, year_cols] <- as.list(replace(unlist(src), is.na(unlist(src)), 0))
    }
  }
}
data <- bind_rows(out, added_wide)

# ---- checks ------------------------------------------------------------------
yrs_num <- as.numeric(year_cols)
chk <- function(name, ok, detail) data.frame(check = name, result = ifelse(ok, "PASS", "FAIL"), detail = detail)
tot_rev  <- added %>% filter(Variable == "Revenue|Government|K-ETS") %>% select(Scenario, year, total = value)
eip_rev  <- added %>% filter(Variable == "Revenue|Government|Energy and Industrial Processes") %>% select(Scenario, year, eip = value)
rev_diff <- full_join(tot_rev, eip_rev, by = c("Scenario", "year")) %>% mutate(d = abs(coalesce(total, 0) - coalesce(eip, 0)))
share_ok <- class_price %>% filter(!is.na(paid))
checks <- rbind(
  chk("step1 rows unchanged", isTRUE(kgx_fill_headline) || identical(as.data.frame(data[seq_len(nrow(report)), ]), as.data.frame(report)),
      if (isTRUE(kgx_fill_headline)) "kgx_fill_headline = TRUE: Price|Carbon and Revenue|Government of the region replaced"
      else paste(nrow(report), "rows, identical to", basename(report_file))),
  chk("paid shares within 0-100 %", all(share_ok$paid >= -1e-9 & share_ok$paid <= 1 + 1e-9),
      paste0("range ", round(100 * min(share_ok$paid), 1), "-", round(100 * max(share_ok$paid), 1), " %")),
  chk("revenue by class = revenue by sector (Energy and Industrial Processes)", max(rev_diff$d) < 1e-9,
      paste("largest difference", signif(max(rev_diff$d), 3), U_REV)),
  chk("every covered technology placed in the emissions tree", TRUE, paste(nrow(techs), "technologies,", length(unique(mapped$var)), "sector variables")),
  chk("covered CO2 within the region's Emissions|CO2|Energy and Industrial Processes", {
        e <- added %>% filter(Variable == "Emissions|CO2|K-ETS") %>%
          inner_join(sector_emis %>% filter(var == "Emissions|CO2|Energy and Industrial Processes") %>% mutate(year = as.character(year)),
                     by = c("Scenario" = "scenario", "year"))
        all(e$value <= e$emis + 1e-6) }, "covered CO2 <= all energy and industrial CO2 in every year")
)
print(checks, row.names = FALSE)

# ---- definitions -------------------------------------------------------------
defs <- added_wide %>% distinct(Variable, Unit) %>% arrange(Variable) %>%
  mutate(Definition = case_when(
    Variable == "Price|Carbon|K-ETS" ~ paste0("K-ETS allowance price at face value (market ", face_name, "). The step1 row Price|Carbon of ", kgx_region, " stays 0: gcamreport only maps <region>CO2 markets."),
    startsWith(Variable, "Price|Carbon|K-ETS|") ~ "Price the class pays per tonne: allowance price x share of its allocation paid for (linked market of the class).",
    startsWith(Variable, "Allocation|K-ETS|Paid Share|") ~ "Share of its allocation the class buys (price of the class market / allowance price, as applied in the run).",
    startsWith(Variable, "Allocation|K-ETS|Free Share|") ~ "Share of its allocation the class receives free = 100 - paid share.",
    Variable == "Emissions|CO2|K-ETS" ~ "CO2 of the technologies covered by the K-ETS price (tagged with a class gas). CCS and biomass technologies are not covered.",
    startsWith(Variable, "Emissions|CO2|K-ETS|") ~ "Covered CO2 of the class.",
    Variable == "Revenue|Government|K-ETS" ~ "K-ETS revenue = sum over classes of class price x covered CO2 (assumes the paid part of the allocation equals the paid part of emissions).",
    startsWith(Variable, "Revenue|Government|K-ETS|") ~ "K-ETS revenue paid by the class.",
    startsWith(Variable, "Revenue|Government|") ~ "K-ETS revenue paid by the technologies of this sector of gcamreport's Emissions|CO2 tree (co2_tech_map).",
    startsWith(Variable, "Price|Carbon|") ~ "Average carbon price paid per tonne of the sector's CO2 = Revenue|Government|<sector> / Emissions|CO2|<sector>; uncovered CO2 of the sector pays 0.",
    TRUE ~ ""))
checks_sheet <- checks
info <- data.frame(item = c("settings", "step1 report", "project", "classes", "units", "built"),
                   value = c(Sys.getenv("KAIST_CONFIG"), report_file, dat_file, kgx_classes_file,
                             paste0("prices ", U_PRICE, " (1990$/tC x ", signif(usd_per_tc_to_usd2010_per_tco2, 6), "), revenue ", U_REV),
                             format(Sys.time(), "%Y-%m-%d %H:%M")))

xlsx <- file.path(output_dir, paste0(run_name, "_kgx.xlsx"))
writexl::write_xlsx(list(data = data, kgx_variables = defs, checks = checks_sheet, info = info), xlsx)
utils::write.csv(data, sub("\\.xlsx$", ".csv", xlsx), row.names = FALSE, na = "")
cat("\nwrote", xlsx, "\n  step1 rows:", nrow(report), " added rows:", nrow(added_wide), " added variables:", nrow(defs), "\n")
if (any(checks$result == "FAIL")) stop("a check failed (sheet checks)")
