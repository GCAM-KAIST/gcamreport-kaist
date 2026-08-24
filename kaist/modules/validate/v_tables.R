################################################################################
# v_tables: all data-driven rule tables for step5 validation.
# Child sets and comparators were numerically confirmed on DB26 outputs
# (2026-08-24). Add rows here to extend coverage.
################################################################################

# --- Checkpoint A: raw query sums vs step1 report -----------------------------
# mode: full = numeric + coverage, total_only = numeric, coverage_only = mapping
# query_names / filter_exprs / join_keys are ";"-separated (aligned for queries).
# When map_prefix is set, the numeric side sums only query keys the mapping
# reports (var != NoReported/NA) -- mirrors the upstream join+filter. Numeric
# checks cover years <= min(final_year, max_year); NA max_year = no cap.
step5_aggregates <- tribble(
  ~aggregate_id,  ~mode,           ~query_names,                                                                ~filter_exprs,                    ~prep,          ~map_prefix,              ~join_keys,                      ~report_vars_add,                                    ~report_vars_subtract,                        ~factor,   ~tol_rel, ~max_year, ~note,
  "fe_nontrn",    "full",          "final energy consumption by sector and fuel",                               "!startsWith(sector, \"trn\")",   "",             "final_energy_map",       "sector;input",                  "Final Energy",                                      "Final Energy|Transportation (w/ bunkers)",   1,         1e-6,     NA,        "report Final Energy includes Bunkers; KAIST irnstl-ceiling inputs are NoReported",
  "fe_transport", "full",          "transport final energy by mode and fuel",                                   "",                               "",             "transport_final_en_map", "sector;input;mode",             "Final Energy|Transportation (w/ bunkers)",          "",                                           1,         1e-6,     NA,        "transport query includes intl bunkers",
  "se_elec",      "full",          "elec gen by gen tech",                                                      "",                               "elec_output",  "secondary_energy_map",   "output;subsector;technology",   "Secondary Energy|Electricity",                      "",                                           1,         1e-6,     NA,        "output='electricity' injected before join",
  "co2_total",    "total_only",    "CO2 emissions by region",                                                   "",                               "",             "",                       "",                              "Emissions|CO2|Energy and Industrial Processes",     "",                                           3.666667,  1e-2,     2035,      "raw-vs-E&IP identity holds only to 2035; later negative-emissions accounting diverges (upstream check has same gap)",
  "co2_tech",     "coverage_only", "CO2 emissions by tech (excluding resource production)",                     "",                               "",             "co2_tech_map",           "sector;subsector;technology",   "",                                                  "",                                           3.666667,  NA,       NA,        "coverage of co2_tech_map; numeric repro blocked by bio corrections",
  "co2_resource", "coverage_only", "CO2 emissions by resource production",                                      "",                               "",             "co2_resource_map",       "resource;subresource;ghg",      "",                                                  "",                                           3.666667,  NA,       NA,        "coverage of co2_resource_map",
)

# --- Checkpoint B: legitimate step1 -> step2 differences ----------------------
# scope: "all" = B1 (step1 vs step2 all-regions), "korea" = B2 (Part B).
# type: replaced/scaled/overwritten = exempt from equality; unit_only = compare
# values with Unit ignored; added = new rows created by the module.
# verify: "exists" = warn if no new-side row matches (module may not have run).
step5_exceptions <- tribble(
  ~pattern,                                                                  ~scope,  ~type,         ~module, ~verify,  ~note,
  "^Price\\|Carbon",                                                         "all",   "replaced",    "a1",    "exists", "rebuilt from CO2 prices query",
  "\\|Battery Storage$",                                                     "all",   "replaced",    "a2",    "exists", "rebuilt from PV/wind storage gen",
  "^Primary Energy\\|(Solar|Wind|Hydro|Nuclear|Geothermal)",                 "all",   "scaled",      "a3",    "exists", "2.1x direct-equivalent factor + Gen III nuclear",
  "^Primary Energy$",                                                        "all",   "scaled",      "a3",    "none",   "receives the a3 top-level deltas",
  "^Capacity\\|Electricity",                                                 "all",   "overwritten", "a4/a5", "none",   "vintage recalc + parent sums",
  "^Production\\|Chemicals\\|High-Value Chemicals$",                         "all",   "unit_only",   "a6",    "none",   "unit relabel Mt/yr -> EJ/yr, values unchanged",
  "^Emissions\\|(CO2|N2O|CH4)\\|Energy$",                                    "korea", "scaled",      "b1",    "exists", "intl bunkers removed (years >= 2020)",
  "^Emissions\\|(CO2|N2O|CH4)\\|Energy\\|Demand$",                           "korea", "scaled",      "b1",    "none",   "",
  "^Emissions\\|(CO2|N2O|CH4)\\|Energy\\|Demand\\|Transportation$",          "korea", "scaled",      "b1",    "none",   "",
  "^Emissions\\|(CO2|N2O|CH4)\\|Energy\\|Demand\\|Transportation\\|Domestic (Aviation|Shipping)$", "korea", "scaled", "b1", "none", "",
  "^Emissions\\|(CO2|N2O|CH4)\\|Energy\\|Demand\\|Bunkers",                  "korea", "scaled",      "b1",    "none",   "",
  "^Primary Energy\\|(Biomass|Coal|Gas|Electricity)\\|Hydrogen$",            "korea", "added",       "b2",    "exists", "derived from Secondary Energy + coefs",
  "^Primary Energy\\|Biomass\\|Electricity$",                                "korea", "added",       "b2",    "exists", "",
  "^Final Energy\\|Industry\\|Iron and Steel\\|Coal\\|(Fuel|Feedstock)$",    "korea", "added",       "b3",    "exists", "identity checked separately (identity_b3)",
  "^Energy Service\\|Transportation\\|(Passenger\\|Road\\|Light-Duty Vehicle|Freight\\|Truck)", "korea", "scaled", "b4", "exists", "pkm/tkm -> thousand vehicles",
  "^Final Energy(\\|.*)?\\|Liquids$",                                        "korea", "scaled",      "b5",    "exists", "x (1 - bio_share); identity checked separately",
  "\\|[Bb]iomass\\|Liquids$",                                                "korea", "added",       "b5",    "exists", "identity checked separately (identity_b5)",
)

# --- Checkpoint B: b5 source <-> Biomass|Liquids pairs (mirror of b5 targets) -
step5_b5_pairs <- tribble(
  ~bioliq_variable,                                              ~source_variables,
  "Final Energy|Biomass|Liquids",                                "Final Energy|Liquids",
  "Final Energy|Industry|Biomass|Liquids",                       "Final Energy|Industry|Liquids;Final Energy|Non-Energy Use|Liquids",
  "Final Energy|Industry|Chemicals|Biomass|Liquids",             "Final Energy|Industry|Chemicals|Liquids",
  "Final Energy|Industry|Iron and Steel|Biomass|Liquids",        "Final Energy|Industry|Iron and Steel|Liquids",
  "Final Energy|Industry|Non-Metallic Minerals|Biomass|Liquids", "Final Energy|Industry|Non-Metallic Minerals|Cement|Liquids",
  "Final Energy|Industry|Other Sector|biomass|Liquids",          "Final Energy|Industry|Other Sector|Liquids",
  "Final Energy|Transportation|Biomass|Liquids",                 "Final Energy|Transportation|Liquids",
  "Final Energy|Transportation|Road|Biomass|Liquids",            "Final Energy|Transportation|Bus|Liquids;Final Energy|Transportation|Light-Duty Vehicle|Liquids;Final Energy|Transportation|Truck|Liquids",
  "Final Energy|Transportation|Rail|Biomass|Liquids",            "Final Energy|Transportation|Rail|Liquids",
  "Final Energy|Transportation|Ship|Biomass|Liquids",            "Final Energy|Transportation|Domestic Shipping|Liquids",
  "Final Energy|Transportation|Air|Biomass|Liquids",             "Final Energy|Transportation|Domestic Aviation|Liquids",
  "Final Energy|Building|Biomass|Liquids",                       "Final Energy|Residential and Commercial|Liquids",
  "Final Energy|Building|Residential|Biomass|Liquids",           "Final Energy|Residential|Liquids",
  "Final Energy|Building|Commercial/Public|Biomass|Liquids",     "Final Energy|Commercial|Liquids",
  "Final Energy|AFOFI|Biomass|Liquids",                          "Final Energy|Agriculture|Liquids",
)

# --- Checkpoint C: parent = sum(children) relations ---------------------------
# stages: ";"-separated subset of step1 / step2_all / step2_korea.
step5_relations <- tribble(
  ~relation_id,        ~stages,                        ~parent,                                          ~children,
  "fe_fuels",          "step1;step2_all",              "Final Energy",                                   "Final Energy|Electricity;Final Energy|Gases;Final Energy|Heat;Final Energy|Hydrogen;Final Energy|Liquids;Final Energy|Solids;Final Energy|Other",
  "fe_fuels_korea",    "step2_korea",                  "Final Energy",                                   "Final Energy|Electricity;Final Energy|Gases;Final Energy|Heat;Final Energy|Hydrogen;Final Energy|Liquids;Final Energy|Solids;Final Energy|Other;Final Energy|Biomass|Liquids",
  "fe_sectors",        "step1;step2_all;step2_korea",  "Final Energy",                                   "Final Energy|Agriculture;Final Energy|Industry;Final Energy|Non-Energy Use;Final Energy|Residential and Commercial;Final Energy|Transportation;Final Energy|Carbon Management;Final Energy|Other Sector;Final Energy|Bunkers",
  "fe_rc",             "step1;step2_all;step2_korea",  "Final Energy|Residential and Commercial",        "Final Energy|Residential;Final Energy|Commercial",
  "fe_industry_fuels", "step1;step2_all",              "Final Energy|Industry",                          "Final Energy|Industry|Electricity;Final Energy|Industry|Gases;Final Energy|Industry|Heat;Final Energy|Industry|Hydrogen;Final Energy|Industry|Liquids;Final Energy|Industry|Solids;Final Energy|Industry|Other",
  "se_elec_sources",   "step1;step2_all;step2_korea",  "Secondary Energy|Electricity",                   "Secondary Energy|Electricity|Biomass;Secondary Energy|Electricity|Coal;Secondary Energy|Electricity|Gas;Secondary Energy|Electricity|Geothermal;Secondary Energy|Electricity|Hydro;Secondary Energy|Electricity|Nuclear;Secondary Energy|Electricity|Oil;Secondary Energy|Electricity|Solar;Secondary Energy|Electricity|Wind;Secondary Energy|Electricity|Other",
  "se_elec_fossil",    "step1;step2_all;step2_korea",  "Secondary Energy|Electricity|Fossil",            "Secondary Energy|Electricity|Coal;Secondary Energy|Electricity|Gas;Secondary Energy|Electricity|Oil",
  "se_elec_nbr",       "step1;step2_all;step2_korea",  "Secondary Energy|Electricity|Non-Biomass Renewables", "Secondary Energy|Electricity|Geothermal;Secondary Energy|Electricity|Hydro;Secondary Energy|Electricity|Solar;Secondary Energy|Electricity|Wind",
  "co2_top",           "step1;step2_all",              "Emissions|CO2",                                  "Emissions|CO2|Energy;Emissions|CO2|Industrial Processes;Emissions|CO2|AFOLU;Emissions|CO2|Other;Emissions|CO2|Other Capture and Removal",
  "co2_eip",           "step1;step2_all",              "Emissions|CO2|Energy and Industrial Processes",  "Emissions|CO2|Energy;Emissions|CO2|Industrial Processes",
  "cap_coal",          "step2_all;step2_korea",        "Capacity|Electricity|Coal",                      "Capacity|Electricity|Coal|w/ CCS;Capacity|Electricity|Coal|w/o CCS",
  "cap_gas",           "step2_all;step2_korea",        "Capacity|Electricity|Gas",                       "Capacity|Electricity|Gas|w/ CCS;Capacity|Electricity|Gas|w/o CCS",
  "cap_oil",           "step2_all;step2_korea",        "Capacity|Electricity|Oil",                       "Capacity|Electricity|Oil|w/ CCS;Capacity|Electricity|Oil|w/o CCS",
  "cap_biomass",       "step2_all;step2_korea",        "Capacity|Electricity|Biomass",                   "Capacity|Electricity|Biomass|w/ CCS;Capacity|Electricity|Biomass|w/o CCS",
  "cap_solar",         "step2_all;step2_korea",        "Capacity|Electricity|Solar",                     "Capacity|Electricity|Solar|PV;Capacity|Electricity|Solar|CSP",
  "cap_wind",          "step2_all;step2_korea",        "Capacity|Electricity|Wind",                      "Capacity|Electricity|Wind|Onshore;Capacity|Electricity|Wind|Offshore",
  "cap_fossil",        "step2_all;step2_korea",        "Capacity|Electricity|Fossil",                    "Capacity|Electricity|Coal;Capacity|Electricity|Gas;Capacity|Electricity|Oil",
  "cap_nbr",           "step2_all;step2_korea",        "Capacity|Electricity|Non-Biomass Renewables",    "Capacity|Electricity|Solar;Capacity|Electricity|Wind;Capacity|Electricity|Hydro;Capacity|Electricity|Geothermal",
)

# --- Checkpoint C: relations that must NOT be asserted (documented gaps) ------
step5_known_violations <- tribble(
  ~violation_id,       ~stages,                        ~reason,
  "co2_totals_korea",  "step2_korea",                  "b1 removes intl bunkers from Emissions|*|Energy but leaves Emissions|CO2 and Energy and Industrial Processes totals unadjusted (28.6 Mt CO2 gap in DB26 2030)",
  "capacity_total",    "step1;step2_all;step2_korea",  "Capacity|Electricity grand total is never recomputed after a2/a4 change children",
  "primary_energy",    "step2_all;step2_korea",        "a3 nuclear add + b2 Primary Energy|*|Hydrogen / |Biomass|Electricity rows sit outside the Primary Energy total",
  "battery_storage",   "step2_all;step2_korea",        "a2 Battery Storage capacity is outside the Solar/Wind parents by design",
  "cap_parents_step1", "step1",                        "step1 capacity parents double-count (upstream bug) -- only valid after a5",
  "fe_industry_korea", "step2_korea",                  "b5 Industry Biomass|Liquids includes the Non-Energy Use share (matches KMIP Industry|Oil scope), so Industry fuel children exceed the GCAM-side parent by NEU x bio_share (~0.3%)",
)
