################################################################################
# Unit conversion table shared by step4 (template fill) and step5 (validation).
# Extracted from step4_fill_template.R so both steps use the same factors.
################################################################################

unit_table <- tibble::tribble(
  ~from,                 ~to,                    ~factor,
  "EJ",                  "ktoe",                 23884.589,
  "EJ/yr",               "ktoe/yr",              23884.589,
  "EJ/yr",               "GWh/yr",               277777.7777778,
  "TWh/yr",              "GWh/yr",               1000,
  "USD_2010/kW",         "thousandKRW/kW",       1.283669,
  "billion USD_2010/yr", "billionKRW/yr",        1283.669079,
  "billion 1975 USD/yr", "billionKRW/yr",        4138.360201,
  "billion USD_2010/yr", "trillionKRW/yr",       1.283669,
  "USD_2010/t CO2",      "KRW/tCO2",             1283.669079,
  "kt N2O/yr",           "Mt CO2eq/yr",          0.273,
  "Mt CH4/yr",           "Mt CO2eq/yr",          27.2,
  "GW/yr",               "GW",                   1,
  "Mt CO2/yr",           "Mt CO2/yr",            1,
  "1990$/tC",            "KRW/tCO2",             530.702,
  "Mt CO2/yr",           "Mt CO2eq/yr",          1,
  # 2015 KRW base conversions
  # 2015 exchange rate: 1 USD = 1,131 KRW
  # US GDP Deflator: 1990=63.6, 2010=91.0, 2015=100
  "1990$/tC",            "2015 KRW/tCO2",        484.85,    # (12/44) * (100/63.6) * 1131
  "billion USD_2010/yr", "2015 billionKRW/yr",   1242.97,   # (100/91.0) * 1131
)
