# GCAM Report - KAIST KMIP Workflow

## Project Overview

This is a fork of the [gcamreport](https://github.com/bc3LC/gcamreport) R package (by BC3 Research) that produces IAMC-format reports from GCAM (Global Change Analysis Model) output. The `kaist-workflow` branch adds a 5-step pipeline for **KMIP (Korea Mid-century Integrated Planning)** reporting, targeting South Korea with GCAM 7.0 output.

## Repository Structure

```
gcamreport/                  # Root - gcamreport R package
├── R/                       # Package R source (functions.R, etc.)
├── inst/extdata/            # Package data (mappings, saveDataFiles)
├── data/                    # .rda files (cf_rgn_v7.0.rda, cf_gcam_v7.0.rda) - git-ignored
├── kaist/                   # KMIP workflow scripts (this project's main work)
│   ├── config.R             # Shared configuration for all steps
│   ├── rgcam_patch.R        # Monkey-patch for rgcam BaseX 9.5+ compatibility
│   ├── step1_generate_report.R
│   ├── step2_process_data.R
│   ├── step3_create_mapping.R
│   ├── step4_fill_template.R
│   ├── step5_verification.qmd
│   └── data/                # Coefficient files (L225, L223 CSVs)
└── kmip/                    # Project data directory (git-ignored)
    └── DB25_output/         # Output files, templates, mappings
```

## Workflow Pipeline

```
Step 1 (generate_report.R)
  → Query GCAM BaseX database via rgcam → .xlsx + .prj

Step 2 (process_data.R)
  → Post-process: bug fixes + Korea-specific calculations → .csv

Step 3 (create_mapping.R)
  → Auto-match GCAM vars to KMIP template → mapping_template.xlsx
  → [MANUAL STEP: user reviews mapping]

Step 4 (fill_template.R)
  → Apply mapping (add/subtract), unit conversion → final .csv

Step 5 (verification.qmd)
  → Compare automated vs manual reporting → HTML/PDF report
```

## Key Technical Details

### Step 2 Processing (most complex, ~700 lines)

**Part A - All Regions:**
- CO2 price extraction from GCAM market data
- Battery storage capacity from PV_storage/wind_storage generation + capacity factors
- Gen_III_Korea generation → added to Primary Energy|Nuclear (gcamreport misses this)
- 2.1x multiplier for renewable primary energy (direct equivalent → physical energy content)
- Vintage-based Capacity|Electricity recalculation (fixes gcamreport CF averaging bug)
- Production|Chemicals|High-Value Chemicals unit fix (EJ mislabeled as Mt/yr)

**Part B - Korea Only:**
- Bunker emission reallocation: aviation 9.3% domestic, shipping 3.2% domestic
- Primary Energy from Secondary Energy using H2 coefficients and electricity efficiency
- Energy Service → vehicle capacity conversion using MT 2020 reference ratios

### Known gcamreport Bugs (worked around in step2)

1. **CF averaging bug**: cf_iea duplicates cause incorrect averaging with cf_rgn → fixed via vintage-based recalculation
2. **Gen_III_Korea missing**: Korea-specific nuclear tech not recognized → manually added to Primary Energy|Nuclear
3. **HVC unit bug**: Production|Chemicals|High-Value Chemicals EJ values labeled Mt/yr → relabeled
4. **CO2 prices**: Not properly extracted per-region → replaced with direct query
5. **rgcam BaseX 9.5+**: Deprecated `-i` flag → patched in rgcam_patch.R to use `-c "OPEN DB; ..."` syntax

### Variable Naming Convention

IAMC pipe-delimited format:
- `Emissions|CO2|Energy|Demand|Transportation`
- `Primary Energy|Nuclear`
- `Capacity|Electricity|Solar|PV`
- `Secondary Energy|Hydrogen|Domestic|Gas|w/ CCS`

### Unit Conversions (step4)

- Energy: EJ → ktoe (×23,884.589), EJ/yr → GWh/yr (×277,777.78)
- Currency: USD_2010 → KRW (×1,283.669), 1990$/tC → KRW/tCO2 (×530.702)
- Emissions: kt N2O/yr → Mt CO2eq/yr (×0.273), Mt CH4/yr → Mt CO2eq/yr (×27.2)

### Mapping Template Format (step3 → step4)

Excel with columns: `template_variable`, `gcam_variable` (base), `gcam_variable_add` (semicolon-separated), `gcam_variable_subtract` (semicolon-separated)

## Configuration (config.R)

- Project: `kmip2025`
- Database: `C:/GCAM/gcamreport/kmip/DB25`
- Output: `C:/GCAM/gcamreport/kmip/DB25_output`
- Region: South Korea
- GCAM version: 7.0
- Year range: 2005–2050

## Tech Stack

R (dplyr, tidyr, readxl, openxlsx, writexl, rgcam, ggplot2), Quarto, GCAM 7.0, BaseX

## Git

- Branch: `kaist-workflow` (main working branch)
- Upstream: bc3LC/gcamreport
- `data/` and `kmip/` directories are git-ignored (large .rda and database files)

## Coding Conventions

- All step scripts source `kaist/config.R` at the top
- Use `devtools::load_all(".")` to load the gcamreport package in development mode
- Year columns are character strings matching `^[0-9]{4}$` pattern
- Data is processed as data.frame (not tibble) when row-level assignment is needed
- Comments in Korean are acceptable for internal notes
