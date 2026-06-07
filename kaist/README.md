# KAIST GCAM Reporting Workflow

## Overview

This folder contains the KAIST 5-step pipeline that turns GCAM output into
KMIP report tables. The rest of
the repository is the original [bc3LC/gcamreport](https://github.com/bc3LC/gcamreport)
R package, used as-is.

## Folder Structure

```
gcamreport-kaist/
├── R/, inst/, data/           # Original gcamreport R package (untouched)
├── kaist/                     # KAIST custom scripts (this folder)
│   ├── config.R               # Shared configuration for all steps
│   ├── step1_generate_report.R
│   ├── step2_process_data.R
│   ├── step3_create_mapping.R
│   ├── step4_fill_template.R
│   ├── step5_verification.qmd
│   ├── rgcam_patch.R          # BaseX 9.5+ compatibility fix
│   ├── data/                  # Coefficient files (L223, L225 CSVs)
│   └── docs/                  # Bug analyses and other technical notes
└── kmip/                      # Local GCAM databases (gitignored)
    ├── DB25/, DB26/, ...      # One BaseX folder per scenario set
    └── DB26_output/           # Pipeline outputs land here
        ├── {run_name}.xlsx
        ├── {run_name}.csv
        ├── {run_name}_korea.csv
        └── {run_name}_project_*.dat
```

## Workflow Scripts

| Step | Script | Purpose |
|------|--------|---------|
| 1 | `step1_generate_report.R` | Query GCAM database, generate base report |
| 2 | `step2_process_data.R` | Post-process data (CO2 prices, battery storage, Korea adjustments) |
| 3 | `step3_create_mapping.R` | Create variable mapping template |
| 4 | `step4_fill_template.R` | Apply mappings and unit conversions |
| 5 | `step5_verification.qmd` | Generate verification report (Manual vs Auto comparison) |

## Key Improvements

1. **Separated KAIST code from the original package**
   - Original gcamreport code in `R/` and `inst/` is untouched.
   - Easy to sync with bc3LC upstream updates.

2. **Shared configuration (`config.R`)**
   - One file for run name, database, region, and year range.
   - No need to edit multiple step scripts when changing the run.

3. **Per-database output folder**
   - Outputs are written under `kmip/{db_name}_output/`, so different
     databases (DB25, DB26, ...) do not mix.

## Quick Start

1. Open R in the repo root and run `devtools::load_all(".")` once to
   build the gcamreport package locally.
2. Edit `kaist/config.R`: set `run_name`, `db_name`, `target_region`,
   and the year range.
3. If BaseX 9.5+ is installed, source `kaist/rgcam_patch.R` once per
   session before step 1 (see the comment block in step1).
4. Run the steps in order:
   `step1_generate_report.R` -> `step2_process_data.R` ->
   `step3_create_mapping.R` -> `step4_fill_template.R` ->
   `step5_verification.qmd`.

## References

- [rgcam_patch.R](rgcam_patch.R) - Fix for BaseX 9.5+ compatibility
