# [2026-10-08: K-TRACES] Post-process the step1 gcamreport output into the K-TRACES workbook.
################################################################################
# build_ktraces_workbook.R
#
# Input : {output_dir}/{run_name}.csv  (merged step1 report, IAMC format, USD_2010)
# Output: {output_dir}/{run_name}_ktraces.xlsx
#   README, IAMC_raw_data (South Korea, USD_2010 -> USD_2025) and one sheet per
#   requested variable group for South Korea. Every number in the variable
#   sheets is an IAMC_raw_data value or a sum/difference/ratio of IAMC_raw_data values;
#   the `Source` column gives the formula.
#
# Run from the repo root after step1:  Rscript kaist-pj/ktraces/build_ktraces_workbook.R
################################################################################
suppressMessages({library(dplyr); library(tidyr); library(readr); library(openxlsx)})
source(file.path(getwd(), "kaist-pj/core/config.R"))

REGION <- "South Korea"
YEARS  <- as.character(c(2021, seq(2025, 2050, 5)))
EJ2TWH <- 1e6 / 3600

# ---- USD_2010 -> USD_2025 (US GDP deflator, BEA A191RD3A086NBEA via FRED) ----------------------
defl_file <- "/home/jin-lee/ktraces/gcamreport_ssp2_ndc/FRED_A191RD3A086NBEA_20261008.csv"
defl <- read.csv(defl_file); defl <- setNames(defl[[2]], substr(defl[[1]], 1, 4))
USD2025 <- defl[["2025"]] / defl[["2010"]]

rep <- read_csv(file.path(output_dir, paste0(run_name, ".csv")), show_col_types = FALSE)
ycols <- grep("^[0-9]{4}$", names(rep), value = TRUE)
is_usd <- grepl("USD_2010", rep$Unit)
rep[is_usd, ycols] <- rep[is_usd, ycols] * USD2025
rep$Unit <- sub("USD_2010", "USD_2025", rep$Unit)
# gcamreport bug (see kaist/kmip/modules/a6_hvc_units.R): high-value chemicals are GCAM
# "chemical" output in EJ but labelled Mt/yr. Fix the label only, as KMIP step2 does.
rep$Unit[rep$Variable == "Production|Chemicals|High-Value Chemicals"] <- "EJ/yr"

scen <- unique(rep$Scenario)
kor <- rep %>% filter(Region == REGION) %>% select(Scenario, Variable, Unit, all_of(YEARS))
long <- kor %>% pivot_longer(all_of(YEARS), names_to = "year") %>% mutate(value = coalesce(value, 0))
grid <- expand_grid(Scenario = scen, year = YEARS)
# value of one IAMC variable (0 when not reported, e.g. aluminum in Korea)
V <- function(var) grid %>% left_join(long %>% filter(Variable == var) %>% select(Scenario, year, value),
                                      by = c("Scenario", "year")) %>% mutate(value = coalesce(value, 0))
# signed combination of IAMC variables: terms = c("+A", "-B")
combo <- function(terms) {
  out <- grid %>% mutate(value = 0)
  for (t in terms) out$value <- out$value + ifelse(substr(t, 1, 1) == "-", -1, 1) * V(substring(t, 2))$value
  out
}
wide <- function(d, keys) d %>% mutate(Scenario = factor(Scenario, scen)) %>%
  select(all_of(c(keys, "year", "value"))) %>% pivot_wider(names_from = year, values_from = value) %>%
  arrange(Scenario) %>% mutate(Scenario = as.character(Scenario))

# ---- sector definitions (11 categories + other end uses) ------------------------------------------
FE <- "Final Energy|"
SECT_FE <- list(
  "Iron & Steel"            = c("+Industry|Iron and Steel"),
  "Cement"                    = c("+Industry|Non-Metallic Minerals|Cement"),
  "Chemicals" = c("+Industry|Chemicals", "-Industry|Chemicals|Ammonia"),
  "Fertilizer"      = c("+Industry|Chemicals|Ammonia"),
  "Aluminum"                  = c("+Industry|Non-Ferrous Metals|Aluminum"),
  "Construction"              = c("+Industry|Construction"),
  "Mining"                    = c("+Industry|Mining"),
  "Agriculture"               = c("+Agriculture"),
  "Other industry"            = c("+Industry|Other Sector", "+Industry|Pulp and Paper"),
  "Residential and Commercial" = c("+Residential and Commercial"),
  "Transportation"            = c("+Transportation"),
  "Bunkers"                   = c("+Bunkers"),
  "Direct Air Capture"        = c("+Carbon Management|Direct Air Capture"))
# In GCAM-KAIST Korea, Non-Metallic Minerals is cement only and Non-Ferrous Metals is aluminum
# only (fuel splits exist only at the Cement / Aluminum level), so no remainder is added to
# Other Industry. Checked below.
# feedstocks (Final Energy|Non-Energy Use|...) belong to these categories
SECT_NEU <- list("Chemicals" = "+Chemicals", "Construction" = "+Non-Metallic Minerals",
                 "Other industry" = "+Other Sector")
SECTOR11 <- c("Iron & Steel", "Chemicals", "Cement", "Fertilizer", "Aluminum", "Agriculture",   # order of the
              "Mining", "Construction", "Other industry", "Power", "Refining")                  # GCAM-KAIST figure
FUELS <- c("Electricity", "Gases", "Heat", "Hydrogen", "Liquids", "Solids|Coal", "Solids|Biomass")
src <- function(terms, prefix, suffix = "") paste(sprintf("%s%s%s%s", substr(terms, 1, 1), prefix, substring(terms, 2), suffix), collapse = " ")

# biofuel share of Korean liquids supply, used to split Liquids into Oil / Biofuel
bio_share <- V("Secondary Energy|Liquids|Biomass") %>% rename(b = value) %>%
  left_join(V("Secondary Energy|Liquids") %>% rename(t = value), by = c("Scenario", "year")) %>%
  mutate(share = ifelse(t > 0, b / t, 0)) %>% select(Scenario, year, share)

fe_rows <- function(defs, prefix, basis) bind_rows(lapply(names(defs), function(s) {
  terms <- defs[[s]]
  tot <- combo(paste0(substr(terms, 1, 1), prefix, substring(terms, 2)))
  parts <- lapply(FUELS, function(f) combo(paste0(substr(terms, 1, 1), prefix, substring(terms, 2), "|", f)) %>% mutate(Fuel = f))
  parts <- bind_rows(parts)
  liq <- parts %>% filter(Fuel == "Liquids") %>% left_join(bio_share, by = c("Scenario", "year"))
  parts <- bind_rows(parts %>% filter(Fuel != "Liquids"),
                     liq %>% mutate(value = value * (1 - share), Fuel = "Liquids|Oil") %>% select(-share),
                     liq %>% mutate(value = value * share, Fuel = "Liquids|Biofuel") %>% select(-share))
  other <- tot %>% left_join(parts %>% group_by(Scenario, year) %>% summarise(s = sum(value), .groups = "drop"),
                             by = c("Scenario", "year")) %>% mutate(value = value - s, Fuel = "Other") %>% select(-s)
  bind_rows(parts, other, tot %>% mutate(Fuel = "Total")) %>%
    mutate(Sector = s, Basis = basis, Source = src(terms, prefix, "|<fuel>"))
}))
fe_use <- fe_rows(SECT_FE, FE, "Energy use")
fe_neu <- fe_rows(SECT_NEU, "Final Energy|Non-Energy Use|", "Feedstock (non-energy use)")
fe_all <- bind_rows(fe_use, fe_neu) %>% mutate(Unit = "EJ/yr") %>%
  mutate(value = ifelse(abs(value) < 1e-12, 0, value))
fe_tot <- function(s, basis = "Energy use") fe_all %>% filter(Sector == s, Basis == basis, Fuel == "Total") %>% select(Scenario, year, value)

stopifnot(all(abs(V("Final Energy|Industry|Non-Metallic Minerals")$value - V("Final Energy|Industry|Non-Metallic Minerals|Cement")$value) < 1e-9),
          all(abs(V("Final Energy|Industry|Non-Ferrous Metals")$value - V("Final Energy|Industry|Non-Ferrous Metals|Aluminum")$value) < 1e-9))
# check: 11-category industry energy use adds up to Final Energy|Industry
ind_names <- setdiff(names(SECT_FE), c("Agriculture", "Residential and Commercial", "Transportation", "Bunkers", "Direct Air Capture"))
chk_fe <- fe_use %>% filter(Fuel == "Total", Sector %in% ind_names) %>% group_by(Scenario, year) %>%
  summarise(s = sum(value), .groups = "drop") %>% left_join(V("Final Energy|Industry"), by = c("Scenario", "year"))
stopifnot(all(abs(chk_fe$s - chk_fe$value) < 1e-6))

# ---- CO2 (Scope 1 and Scope 2) ----------------------------------------------------------------
E <- "Emissions|CO2|"
SECT_CO2 <- list(
  "Iron & Steel"            = c("+Energy|Demand|Industry|Iron and Steel"),
  "Cement"                    = c("+Energy|Demand|Industry|Non-Metallic Minerals", "+Industrial Processes|Cement"),
  "Chemicals" = c("+Energy|Demand|Industry|Chemicals", "-Energy|Demand|Industry|Chemicals|Ammonia"),
  "Fertilizer"      = c("+Energy|Demand|Industry|Chemicals|Ammonia"),
  "Aluminum"                  = c("+Energy|Demand|Industry|Non-Ferrous Metals"),
  "Construction"              = c("+Energy|Demand|Industry|Construction"),
  "Mining"                    = c("+Energy|Demand|Industry|Mining"),
  "Agriculture"               = c("+Energy|Demand|AFOFI"),
  "Other industry"            = c("+Energy|Demand|Industry|Other Sector", "+Industrial Processes", "-Industrial Processes|Cement"),
  "Refining"                  = c("+Energy|Supply|Liquids"),
  "Power"                     = c("+Energy|Supply|Electricity"),
  "Residential and Commercial" = c("+Energy|Demand|Residential and Commercial"),
  "Transportation"            = c("+Energy|Demand|Transportation"),
  "Bunkers"                   = c("+Energy|Demand|Bunkers"),
  "Other Energy Supply"       = c("+Energy|Supply|Gases", "+Energy|Supply|Hydrogen", "+Energy|Supply|Fugitive", "+Energy|Supply|Biomass"),
  "Direct Air Capture"        = c("+Other Capture and Removal"))
scope1 <- bind_rows(lapply(names(SECT_CO2), function(s) {
  terms <- SECT_CO2[[s]]
  combo(paste0(substr(terms, 1, 1), E, substring(terms, 2))) %>% mutate(Sector = s, Source = src(terms, E))
})) %>% mutate(Scope = "Scope 1", Unit = "Mt CO2/yr")
# check: sum over sectors = Emissions|CO2 - Emissions|CO2|AFOLU
chk_co2 <- scope1 %>% group_by(Scenario, year) %>% summarise(s = sum(value), .groups = "drop") %>%
  left_join(combo(c("+Emissions|CO2", "-Emissions|CO2|AFOLU")), by = c("Scenario", "year"))
co2_gap <- max(abs(chk_co2$s - chk_co2$value))

# Scope 2: power-sector CO2 allocated by each end use's share of final electricity
ELEC_USERS <- c(setdiff(SECTOR11, c("Refining", "Power")), "Residential and Commercial", "Transportation", "Bunkers", "Direct Air Capture")
elec_use <- fe_use %>% filter(Fuel == "Electricity", Sector %in% ELEC_USERS) %>% select(Scenario, year, Sector, value)
power <- scope1 %>% filter(Sector == "Power") %>% select(Scenario, year, power = value)
scope2 <- elec_use %>% group_by(Scenario, year) %>% mutate(share = if (sum(value) > 0) value / sum(value) else 0 * value) %>% ungroup() %>%
  left_join(power, by = c("Scenario", "year")) %>%
  transmute(Scenario, year, Sector, value = share * power, Scope = "Scope 2", Unit = "Mt CO2/yr",
            Source = "Emissions|CO2|Energy|Supply|Electricity x sector share of final electricity")
chk_s2 <- scope2 %>% group_by(Scenario, year) %>% summarise(s = sum(value), .groups = "drop") %>% left_join(power, by = c("Scenario", "year"))
stopifnot(all(abs(chk_s2$s - chk_s2$power) < 1e-6))
elec_cov <- elec_use %>% group_by(Scenario, year) %>% summarise(s = sum(value), .groups = "drop") %>%
  left_join(V("Final Energy|Electricity"), by = c("Scenario", "year"))
stopifnot(all(abs(elec_cov$s - elec_cov$value) < 1e-6))   # end uses cover all final electricity

# ---- output ---------------------------------------------------------------------------------------
OUT <- tribble(
  ~Sector, ~Item, ~var, ~Unit, ~scale,
  "Iron & Steel", "Steel production", "Production|Iron and Steel|Steel", "Mt/yr", 1,
  "Cement", "Cement production", "Production|Non-Metallic Minerals|Cement", "Mt/yr", 1,
  "Chemicals", "High-value chemicals output (GCAM chemical output)", "Production|Chemicals|High-Value Chemicals", "EJ/yr", 1,
  "Fertilizer", "Ammonia production", "Production|Chemicals|Ammonia", "Mt/yr", 1,
  "Aluminum", "Aluminum production", "Production|Non-Ferrous Metals|Aluminum", "Mt/yr", 1,
  "Other industry", "Paper production (part of Other industry, Mt)", "Production|Pulp and Paper|Paper", "Mt/yr", 1,
  "Refining", "Liquids supply (oil refining and biofuels)", "Secondary Energy|Liquids", "EJ/yr", 1,
  "Power", "Electricity generation", "Secondary Energy|Electricity", "TWh/yr", EJ2TWH,
  "Construction", "Service output (GCAM energy service)", "Service Output|Industry|Construction", "EJ/yr", 1,
  "Mining", "Service output (GCAM energy service)", "Service Output|Industry|Mining", "EJ/yr", 1,
  "Agriculture", "Service output (GCAM energy service)", "Service Output|Agriculture", "EJ/yr", 1,
  "Other industry", "Service output (excl. paper and food processing)", "Service Output|Industry|Other Sector", "EJ/yr", 1)
output <- bind_rows(lapply(seq_len(nrow(OUT)), function(i) V(OUT$var[i]) %>%
  mutate(value = value * OUT$scale[i], Sector = OUT$Sector[i], Item = OUT$Item[i], Unit = OUT$Unit[i], Source = OUT$var[i])))

# ---- intensities ----------------------------------------------------------------------------------
PHYS <- tribble(~Sector, ~out_var, ~e_unit, ~c_unit, ~e_k, ~c_k,
  "Iron & Steel", "Production|Iron and Steel|Steel", "GJ/t", "t CO2/t", 1000, 1,
  "Cement", "Production|Non-Metallic Minerals|Cement", "GJ/t", "t CO2/t", 1000, 1,
  "Chemicals", "Production|Chemicals|High-Value Chemicals", "GJ/GJ output", "kg CO2/GJ output", 1, 1,
  "Fertilizer", "Production|Chemicals|Ammonia", "GJ/t NH3", "t CO2/t NH3", 1000, 1,
  "Aluminum", "Production|Non-Ferrous Metals|Aluminum", "GJ/t", "t CO2/t", 1000, 1,
  "Refining", "Secondary Energy|Liquids", NA, "kg CO2/GJ liquids", NA, 1,
  "Power", "Secondary Energy|Electricity", NA, "g CO2/kWh", NA, 1000 / EJ2TWH)
ratio <- function(num, den, k) num %>% rename(n = value) %>% left_join(den %>% rename(d = value), by = c("Scenario", "year")) %>%
  mutate(value = ifelse(d > 0, n / d * k, NA)) %>% select(Scenario, year, value)
co2_of <- function(s) scope1 %>% filter(Sector == s) %>% select(Scenario, year, value)
ei <- list(); ci <- list()
for (s in SECTOR11) {
  p <- PHYS[PHYS$Sector == s, ]
  has_fe <- s %in% names(SECT_FE)
  if (nrow(p) && !is.na(p$e_unit) && has_fe && !(s %in% names(SECT_NEU)))   # Chemicals: incl.-feedstock row only
    ei[[length(ei) + 1]] <- ratio(fe_tot(s), V(p$out_var), p$e_k) %>% mutate(Sector = s, Denominator = "Physical output", Unit = p$e_unit,
                                  Source = paste0("energy use / ", p$out_var))
  if (has_fe) {
    if (s %in% names(SECT_NEU)) {
      incl <- fe_tot(s) %>% left_join(fe_tot(s, "Feedstock (non-energy use)") %>% rename(f = value), by = c("Scenario", "year")) %>% mutate(value = value + f) %>% select(-f)
      if (nrow(p)) ei[[length(ei) + 1]] <- ratio(incl, V(p$out_var), p$e_k) %>% mutate(Sector = s, Denominator = "Physical output (energy use incl. feedstocks)", Unit = p$e_unit,
                                                   Source = paste0("(energy use + feedstocks) / ", p$out_var))
    }
  }
  if (nrow(p)) ci[[length(ci) + 1]] <- ratio(co2_of(s), V(p$out_var), p$c_k) %>% mutate(Sector = s, Denominator = "Physical output", Unit = p$c_unit,
                                        Source = paste0("Scope 1 CO2 / ", p$out_var))
  if (has_fe) ci[[length(ci) + 1]] <- ratio(co2_of(s), fe_tot(s), 1) %>% mutate(Sector = s, Denominator = "Energy use", Unit = "kg CO2/GJ",
                                           Source = "Scope 1 CO2 / energy use")
}
# [2026-10-09] Energy-service sectors: final energy / service output (professor's definition).
# Numerators match the service output scope: construction and other industry service output
# includes their feedstock sectors, so their feedstocks are added. Other Industry's service
# output covers other industrial energy use and feedstocks; its numerator is Industry|Other
# Sector (which in gcamreport also holds food processing energy) + Non-Energy Use|Other Sector,
# without Pulp and Paper (paper has its own physical output).
SVC <- tribble(~Sector, ~out_var, ~num,
  "Construction",   "Service Output|Industry|Construction", c("+Final Energy|Industry|Construction", "+Final Energy|Non-Energy Use|Non-Metallic Minerals"),
  "Mining",         "Service Output|Industry|Mining",       c("+Final Energy|Industry|Mining"),
  "Agriculture",    "Service Output|Agriculture",           c("+Final Energy|Agriculture"),
  "Other industry", "Service Output|Industry|Other Sector", c("+Final Energy|Industry|Other Sector", "+Final Energy|Non-Energy Use|Other Sector"))
for (i in seq_len(nrow(SVC))) {
  s <- SVC$Sector[i]; den <- V(SVC$out_var[i])
  ei[[length(ei) + 1]] <- ratio(combo(SVC$num[[i]]), den, 1) %>% mutate(Sector = s, Denominator = "Service output", Unit = "GJ/GJ service",
                              Source = paste0("(", paste(SVC$num[[i]], collapse = " "), ") / ", SVC$out_var[i]))
  ci[[length(ci) + 1]] <- ratio(co2_of(s), den, 1) %>% mutate(Sector = s, Denominator = "Service output", Unit = "kg CO2/GJ service",
                              Source = paste0("Scope 1 CO2 / ", SVC$out_var[i]))
}
ei <- bind_rows(ei); ci <- bind_rows(ci)

# ---- prices -----------------------------------------------------------------------------------------
pvars <- grep("^Price\\|Final Energy\\|(Industry|Residential and Commercial|Transportation|Agriculture)\\|[^|]+(\\|(Coal|Biomass))?$",
              unique(kor$Variable), value = TRUE)
prices <- bind_rows(
  lapply(pvars, function(v) V(v) %>% mutate(Sector = sub("^Price\\|Final Energy\\|([^|]+)\\|.*$", "\\1", v),
                                           Fuel = sub("^Price\\|Final Energy\\|[^|]+\\|", "", v), Source = v)),
  V("Price|Secondary Energy|Electricity") %>% mutate(Sector = "Power (generation)", Fuel = "Electricity", Source = "Price|Secondary Energy|Electricity")) %>%
  mutate(Fuel = recode(Fuel, "Liquids" = "Liquids (oil and biofuel)"), Unit = "USD_2025/GJ")
cprice <- V("Price|Carbon") %>% mutate(Item = "Carbon price (Korea GHG cap shadow price)", Unit = "USD_2025/t CO2", Source = "Price|Carbon")

# ---- electricity ---------------------------------------------------------------------------------
gen_vars <- grep("^Secondary Energy\\|Electricity\\|(Coal|Gas|Oil|Nuclear|Solar|Wind|Hydro|Biomass|Geothermal)$", unique(kor$Variable), value = TRUE)
elec <- bind_rows(
  bind_rows(lapply(c("Secondary Energy|Electricity", gen_vars), function(v) V(v) %>%
    mutate(Item = "Generation", Detail = ifelse(v == "Secondary Energy|Electricity", "Total", sub(".*\\|", "", v)), Source = v))),
  elec_use %>% mutate(Item = "Consumption", Detail = Sector, Source = "Final Energy|<sector>|Electricity")) %>%
  mutate(value = value * EJ2TWH, Unit = "TWh/yr") %>% select(-any_of("Sector"))

# ---- workbook --------------------------------------------------------------------------------------
ord11 <- function(d) d %>% mutate(Sector = factor(Sector, unique(c(SECTOR11, names(SECT_FE), names(SECT_CO2))))) %>%
  arrange(Scenario, Sector) %>% mutate(Sector = as.character(Sector))
sheets <- list(
  "1_Energy_price"      = wide(prices, c("Scenario", "Sector", "Fuel", "Unit", "Source")),
  "2_Energy_intensity"  = wide(ord11(ei), c("Scenario", "Sector", "Denominator", "Unit", "Source")),
  "3_Carbon_intensity"  = wide(ord11(ci), c("Scenario", "Sector", "Denominator", "Unit", "Source")),
  "4_Final_energy"      = wide(ord11(fe_all), c("Scenario", "Sector", "Basis", "Fuel", "Unit", "Source")),
  "5_Elec_generation"   = wide(elec %>% filter(Item == "Generation") %>% select(-Item) %>% rename(Source_technology = Detail),
                               c("Scenario", "Source_technology", "Unit", "Source")),
  "6_Sector_elec_consumption" = wide(ord11(elec %>% filter(Item == "Consumption") %>% select(-Item) %>% rename(Sector = Detail)),
                               c("Scenario", "Sector", "Unit", "Source")),
  "7_CO2_emissions"     = wide(ord11(bind_rows(scope1, scope2)), c("Scenario", "Scope", "Sector", "Unit", "Source")),
  "8_Carbon_price"      = wide(cprice, c("Scenario", "Item", "Unit", "Source")),
  "9_Output"            = wide(ord11(output), c("Scenario", "Sector", "Item", "Unit", "Source")))
for (n in names(sheets)) sheets[[n]] <- sheets[[n]] %>% mutate(Scenario = factor(Scenario, scen)) %>% arrange(Scenario) %>% mutate(Scenario = as.character(Scenario))

# [2026-10-09] README: general notes first, then one block per sheet (in sheet order)
readme <- tribble(~Sheet, ~Topic, ~Note,
  "General", "Model", "GCAM-KAIST v9.1, reported with gcamreport (bc3LC; KAIST fork, branch pj-kaist) plus the K-TRACES extensions: Industry|Construction, Industry|Mining, Service Output|..., cement fuel CO2 under Non-Metallic Minerals, regional energy prices.",
  "General", "Region / years", sprintf("%s; %s. 2021 = final calibration year; GCAM model periods only.", REGION, paste(YEARS, collapse = ", ")),
  "General", "Scenarios", paste(scen, collapse = ", "),
  "General", "Currency", sprintf("USD_2010 converted to USD_2025 with the US GDP deflator (BEA A191RD3A086NBEA, FRED 2026-10-08): x %.4f. Applies to every sheet.", USD2025),
  "General", "Industries", "11 industries of GCAM-KAIST: Iron & Steel, Chemicals, Cement, Fertilizer, Aluminum, Agriculture, Mining, Construction, Other industry (industry) + Power, Refining (energy). Contents of each are listed in the 'Industry definitions' table. Rows that are not one of the 11 industries are listed in the 'Non-industry rows' table.",
  "Industry definitions", "Iron & Steel", "GCAM sector: iron and steel. Energy: Final Energy|Industry|Iron and Steel. CO2: Energy|Demand|Industry|Iron and Steel. Output: steel production (Mt).",
  "Industry definitions", "Chemicals", "GCAM sectors: chemical energy use + chemical feedstocks (fertilizer/ammonia excluded). Energy: Final Energy|Industry|Chemicals minus its Ammonia part; feedstocks (naphtha etc.): Final Energy|Non-Energy Use|Chemicals. CO2: Energy|Demand|Industry|Chemicals minus Ammonia. Output: GCAM chemical output (EJ). Energy intensity is given including feedstocks only, because the chemical output includes the feedstock part.",
  "Industry definitions", "Cement", "GCAM sectors: cement + process heat cement. Energy: Final Energy|Industry|Non-Metallic Minerals|Cement. CO2: fuel combustion (Energy|Demand|Industry|Non-Metallic Minerals) + process CO2 (Industrial Processes|Cement). Output: cement production (Mt).",
  "Industry definitions", "Fertilizer", "GCAM sectors: ammonia + N fertilizer (N fertilizer itself has no direct energy use or CO2; Korean domestic ammonia goes entirely to N fertilizer). Energy and CO2: the Industry|Chemicals|Ammonia part. Output: ammonia production (Mt NH3).",
  "Industry definitions", "Aluminum", "GCAM sectors: aluminum + alumina. 0 for Korea in all scenarios (no primary smelting; zero calibrated output). Aluminum rolling/processing is inside Other industry.",
  "Industry definitions", "Agriculture", "GCAM sector: agricultural energy use (energy use only; crop and livestock emissions are not included). Energy: Final Energy|Agriculture. CO2: Energy|Demand|AFOFI. Output: service output (EJ).",
  "Industry definitions", "Mining", "GCAM sector: mining energy use (energy use only; fossil resource production and fugitive emissions are not included). Energy: Final Energy|Industry|Mining. CO2: Energy|Demand|Industry|Mining. Output: service output (EJ).",
  "Industry definitions", "Construction", "GCAM sectors: construction energy use + construction feedstocks (asphalt). Energy: Final Energy|Industry|Construction; feedstocks: Final Energy|Non-Energy Use|Non-Metallic Minerals. CO2: Energy|Demand|Industry|Construction. Output: service output (EJ).",
  "Industry definitions", "Other industry", "GCAM sectors: other industrial energy use + other industrial feedstocks, pulp and paper (paper, process heat paper, waste biomass for paper), food processing. Energy: Final Energy|Industry|Other Sector + Pulp and Paper; feedstocks: Non-Energy Use|Other Sector. CO2: Energy|Demand|Industry|Other Sector + industrial-process CO2 other than cement. Output: paper (Mt) and service output of the rest (EJ). Direct Air Capture is NOT included (separate row).",
  "Industry definitions", "Power", "GCAM sector: electricity generation (all technologies). CO2: Energy|Supply|Electricity. Output: electricity generation (TWh). Its Scope 1 CO2 is what Scope 2 allocates to electricity users.",
  "Industry definitions", "Refining", "GCAM sector: refining (oil refining, coal/gas to liquids, biofuel production). CO2: Energy|Supply|Liquids. Output: liquids supply (EJ).",
  "General", "Source column", "Every value in sheets 1-9 is an IAMC_raw_data value or a sum/difference/ratio of them; the Source column gives the formula.",
  "General", "Changes 2026-10-09", "(1) Service output added for Agriculture, Mining, Construction and Other industry, used for their intensities (sheets 2, 3, 9). (2) Requested 'sector-specific electricity generation' supplied as sector-specific electricity consumption (sheet 6); generation by source moved to its own sheet (sheet 5).",
  "IAMC_raw_data", "Content", "gcamreport output for South Korea: all IAMC variables and years. Only two edits: USD_2010 -> USD_2025, and the unit label of Production|Chemicals|High-Value Chemicals (EJ/yr, see 9_Output).",
  "1_Energy_price", "Content", "Price|Final Energy by end-use sector (Industry, Residential and Commercial, Transportation, Agriculture) and fuel, plus the electricity generation price (Price|Secondary Energy|Electricity). USD_2025/GJ.",
  "1_Energy_price", "Note", "All industry categories face the same industrial fuel price in GCAM.",
  "2_Energy_intensity", "Content", "Energy use / output. Denominators: physical output (Iron & Steel, Chemicals, Cement, Fertilizer) and service output (Agriculture, Mining, Construction, Other industry).",
  "2_Energy_intensity", "Note", "Chemicals: energy use incl. feedstocks / GCAM chemical output (EJ), so GJ/GJ. Refining and Power are not available (gcamreport has no energy inputs to these sectors). Other industry's service-output ratio includes food processing energy in the numerator (not separable in gcamreport).",
  "3_Carbon_intensity", "Content", "Scope 1 CO2 / output (physical or service) and / energy use. Power in g CO2/kWh, Refining in kg CO2/GJ liquids.",
  "4_Final_energy", "Content", "Energy use by sector and fuel (EJ/yr): Electricity, Gases, Heat, Hydrogen, Liquids|Oil, Liquids|Biofuel, Solids|Coal, Solids|Biomass, Other (remainder), Total.",
  "4_Final_energy", "Feedstocks", "IAMC Final Energy excludes feedstocks. Feedstocks (Final Energy|Non-Energy Use) are separate rows, Basis = 'Feedstock (non-energy use)'. Non-Energy Use|Non-Metallic Minerals is construction feedstock (asphalt) and is assigned to Construction.",
  "4_Final_energy", "Oil / Biofuel", "Liquids split with the biofuel share of Korean liquids supply (Secondary Energy|Liquids|Biomass / Secondary Energy|Liquids); IAMC has no split by sector.",
  "5_Elec_generation", "Content", "Electricity generation by source (Secondary Energy|Electricity|...), TWh/yr.",
  "6_Sector_elec_consumption", "Content", "Sector-specific electricity consumption (Final Energy|<sector>|Electricity), TWh/yr. Together with sheet 4 it gives electrification (electricity / Total).",
  "7_CO2_emissions", "Scope 1", sprintf("Direct CO2 by sector (energy and industrial processes); Cement includes process CO2. Sector sum = Emissions|CO2 - Emissions|CO2|AFOLU (max gap %.3f Mt).", co2_gap),
  "7_CO2_emissions", "No bio", "Scope 1 follows the instruction to use CO2 (no bio): it is based on the ModelInterface query 'CO2 emissions by sector (no bio) (excluding resource production)' (gcamreport adjusts its by-sector CO2 to this query). The query moves biomass carbon uptake to the sectors that use biomass, so some sectors can be negative (e.g. Chemicals in 2050).",
  "7_CO2_emissions", "Scope 2", "Power-sector CO2 allocated by each end use's share of final electricity; the sum equals power CO2. Electricity used upstream (e.g. hydrogen production) is not allocated separately.",
  "7_CO2_emissions", "Scope 3", "Not provided.",
  "8_Carbon_price", "Content", "Price|Carbon for South Korea (shadow price of the Korean GHG cap), USD_2025/t CO2. 0 in SSP2-Ref.",
  "9_Output", "Content", "Physical output (Mt, TWh, EJ), and service output (EJ of energy service) for Agriculture, Mining, Construction and Other industry. Other industry has two rows that cannot be added (paper in Mt; service output of the rest in EJ). Refining = total liquids supply (oil refining and biofuels).",
  "9_Output", "Note", "Aluminum is 0 (no primary smelting in Korea). Production|Chemicals|High-Value Chemicals is GCAM chemical output in EJ (gcamreport labels it Mt/yr; label corrected). Production|Chemicals mixes Mt and EJ and is not used.",
  "General", "Checks", "Industry energy-use categories sum to Final Energy|Industry; sector electricity sums to Final Energy|Electricity; sector Scope 1 sums to Emissions|CO2 - AFOLU; Scope 2 sums to power CO2.")
iamc_raw <- rep %>% filter(Region == REGION)   # [2026-10-09] Korea only

# ---- write: README as three tables, then data sheets (openxlsx for layout) ------------------------
wb <- createWorkbook()
st_title <- createStyle(textDecoration = "bold", fontSize = 13)
st_head  <- createStyle(textDecoration = "bold", fgFill = "#D9E1F2", border = "Bottom")
st_wrap  <- createStyle(wrapText = TRUE, valign = "top")
addWorksheet(wb, "README")
writeData(wb, "README", "K-TRACES / GCAM-KAIST v9.1 results for South Korea", startRow = 1)
addStyle(wb, "README", createStyle(textDecoration = "bold", fontSize = 15), rows = 1, cols = 1)
r <- 3
# Two-column tables (General, Industry definitions) put their label in A:B (merged) and the
# text in C, so the long text sits in the same wide column C as in the Sheets table.
put_table <- function(title, df) {
  if (ncol(df) == 2) df <- tibble(a = df[[1]], b = "", c = df[[2]]) %>% setNames(c(names(df)[1], " ", names(df)[2]))
  writeData(wb, "README", title, startRow = r); addStyle(wb, "README", st_title, rows = r, cols = 1)
  writeData(wb, "README", df, startRow = r + 1, headerStyle = st_head)
  rows <- (r + 1):(r + 1 + nrow(df))
  if (names(df)[2] == " ") for (i in rows) mergeCells(wb, "README", cols = 1:2, rows = i)
  addStyle(wb, "README", st_head, rows = r + 1, cols = 1:3, gridExpand = TRUE)
  addStyle(wb, "README", st_wrap, rows = rows[-1], cols = 1:3, gridExpand = TRUE)
  r <<- r + nrow(df) + 3
}
put_table("1. General", readme %>% filter(Sheet == "General") %>% select(Topic, Note))
put_table("2. Industry definitions", readme %>% filter(Sheet == "Industry definitions") %>% select(Industry = Topic, Definition = Note))
nonind <- tribble(~Row, ~`Appears in`, ~Definition,
  "Residential and Commercial", "4, 6, 7", "Buildings (households and services).",
  "Transportation", "4, 6, 7", "Domestic transport.",
  "Bunkers", "4, 6, 7", "International aviation and shipping.",
  "Other Energy Supply", "7", "Gas processing and pipelines, hydrogen production, fugitive CO2, biomass supply.",
  "Direct Air Capture", "4, 6, 7", "DAC energy use and CO2 removal. Not part of Other industry.")
put_table("3. Non-industry rows (used for national totals)", nonind)
put_table("4. Sheets", readme %>% filter(!Sheet %in% c("General", "Industry definitions")) %>% select(Sheet, Topic, Note))
setColWidths(wb, "README", cols = 1:3, widths = c(26, 14, 110))
for (n in c("IAMC_raw_data", names(sheets))) {
  d <- if (n == "IAMC_raw_data") iamc_raw else sheets[[n]]
  # data sheets keep the plain writexl look: bold, centred header only
  addWorksheet(wb, n); writeData(wb, n, d, headerStyle = createStyle(textDecoration = "bold", halign = "center"))
}
saveWorkbook(wb, file.path(output_dir, paste0(run_name, "_ktraces.xlsx")), overwrite = TRUE)
cat("Wrote", file.path(output_dir, paste0(run_name, "_ktraces.xlsx")), "\n")
cat(sprintf("USD_2010 -> USD_2025 factor %.4f | CO2 sector-sum gap %.4f Mt | elec users / Final Energy|Electricity (min, max): %.4f, %.4f\n",
            USD2025, co2_gap, min(elec_cov$s / pmax(elec_cov$value, 1e-12)), max(elec_cov$s / pmax(elec_cov$value, 1e-12))))
for (n in names(sheets)) cat(sprintf("  %-20s %4d rows\n", n, nrow(sheets[[n]])))
