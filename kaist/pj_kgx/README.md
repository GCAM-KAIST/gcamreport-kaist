# pj_kgx: K-ETS rows for the K-GX fund runs

The K-GX fund runs (`pj_gcam_runs/carbon_pricing/input/configuration/kgx_fund_scenarios`) charge South Korea the K-ETS price the K-GX plan needs, by K-ETS class: power, other paying industry, carbon-leakage list. Each class pays the allowance price times the share of its allocation it buys, through linked GCAM markets (`South KoreaCO2_KETS` and `South KoreaCO2_KETS_POWER / _OTHER / _LEAK`).

gcamreport only maps `<region>CO2` markets, so the standard report gives these runs `Price|Carbon` = 0 and `Revenue|Government` = 0 for South Korea. This project keeps every step1 row unchanged and adds the rows that describe the K-ETS.

## Files

```
pj_kgx/
├── config/kgx_fund_ssp2.R   run settings: kgx_fund_db, SSP2_KGX_Central and SSP2_KGX_Leak05
├── functions.R              K-ETS market names (ignore list), class file reader
├── build_kgx_report.R       step1 report + project -> {run_name}_kgx.xlsx / .csv
└── data/
    ├── kgx_queries.xml      query added to the step1 project: CO2 of the covered technologies, by tech
    └── kgx_classes.csv      class markets -> class names
```

## Run (from the repo root)

```
KAIST_CONFIG=kaist/pj_kgx/config/kgx_fund_ssp2.R Rscript kaist/core/step1_generate_report.R
KAIST_CONFIG=kaist/pj_kgx/config/kgx_fund_ssp2.R Rscript kaist/pj_kgx/build_kgx_report.R
```

Step1 is the core step, unchanged. The settings add the K-ETS markets to `ignore_markets` and the pj_kgx query to `project_queries`. The second script writes `{output_dir}/{run_name}_kgx.xlsx`, where `output_dir` is `{db_path}/{db_name}_output`, outside the repo:

- **`data`**: the step1 rows exactly as step1 wrote them, then the added rows. Columns and units are the same as step1.
- **`kgx_variables`**: what each added variable is.
- **`checks`**: four checks:
  - the step1 rows are unchanged;
  - paid shares lie within 0–100 %;
  - revenue by class equals revenue by sector;
  - covered CO2 does not exceed the region's energy and industrial CO2.
- **`info`**: the input files used.

## Used by the kgx scenarios of pj_gcam_runs (2026-11-27)

`pj_gcam_runs/scenarios/v9.1/core/kgx/output/kgx-gcamreport-run.R` runs the two scripts above for every scenario of that folder
(one database per scenario, e.g. `kgx_SSP2_crf44_ets27_EITE0_261126`). It writes its own settings file next to its
outputs, with the lines of `config/kgx_fund_ssp2.R` and `kgx_fill_headline <- TRUE`, so `Price|Carbon` and
`Revenue|Government` of South Korea carry the K-ETS price and revenue. Those scenarios name the third class market
`CO2_KETS_EITE` (class `EITE` in `data/kgx_classes.csv`); the older K-GX fund runs name it `CO2_KETS_LEAK`.

Report all regions (`desired_regions <- "All"`). With a subset of regions step1 gives wrong `Capacity|Electricity`,
`Capacity Additions|Electricity` and `Investment|Energy Supply` rows (South Korea's capacity came out 15 times too
high with two regions); every other row is the same.

## Added rows (South Korea, each K-GX scenario)

| Variable | Unit | Meaning |
|---|---|---|
| `Price\|Carbon\|K-ETS` | USD_2010/t CO2 | allowance price (face value) |
| `Price\|Carbon\|K-ETS\|<class>` | USD_2010/t CO2 | what the class pays per tonne = face × paid share |
| `Allocation\|K-ETS\|Paid Share\|<class>`, `…\|Free Share\|<class>` | % | share of its allocation the class buys / receives free |
| `Emissions\|CO2\|K-ETS[\|<class>]` | Mt CO2/yr | CO2 of the covered technologies |
| `Revenue\|Government\|K-ETS[\|<class>]` | billion USD_2010/yr | class price × covered CO2 |
| `Revenue\|Government\|<sector>` | billion USD_2010/yr | the same by the sectors of gcamreport's `Emissions\|CO2` tree, e.g. `Revenue\|Government\|Energy\|Supply\|Electricity` |
| `Price\|Carbon\|<sector>` | USD_2010/t CO2 | average price paid per tonne of the sector's CO2 = revenue / `Emissions\|CO2\|<sector>` |

`<class>` comes from `data/kgx_classes.csv`. A class market missing from that file stops the script.

## Notes

- **`Price|Carbon` and `Revenue|Government` stay 0** for South Korea by default, so the step1 rows remain identical. The sector rows under `Revenue|Government|…` then sum to more than their 0 parent. Set `kgx_fill_headline <- TRUE` in the settings to write the allowance price into `Price|Carbon` and the K-ETS revenue into `Revenue|Government`.
- **Revenue assumes the paid share applies to emissions.** It is the paid share of the class applied to its covered emissions: allowances are taken to equal emissions, and banking and offsets are left out.
- **Not covered:** technologies with CCS, biomass technologies, buildings and transport. Their CO2 pays 0. It is still counted in the denominator of `Price|Carbon|<sector>`.
- **Conversions:** prices from 1990$/tC as gcamreport does (÷ 44/12 × `conv_90USD_10USD`).
