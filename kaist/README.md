# KAIST GCAM Reporting Workflow

## Overview

This folder contains KAIST-customized scripts for generating GCAM reports, specifically designed for KMIP (Korea Model Intercomparison Project) reporting.

## Repository Changes

### Fork Setup
- Previously: Repository was cloned but not properly forked
- Now: Properly forked from [bc3LC/gcamreport](https://github.com/bc3LC/gcamreport)
- Upstream sync enabled for future updates from original package

### New Folder Structure

```
gcamreport-kaist/
├── R/, inst/, data/        # Original gcamreport package (untouched)
├── kaist/                  # KAIST custom scripts
│   ├── config.R            # Shared configuration
│   ├── step1_generate_report.R
│   ├── step2_process_data.R
│   ├── step3_create_mapping.R
│   ├── step4_fill_template.R
│   ├── step5_verification.qmd
│   ├── rgcam_patch.R       # BaseX compatibility fix
│   └── data/               # Coefficient files
└── projects/               # Output directory (gitignored)
    └── {project_name}/
        ├── template.xlsx
        ├── mapping_template.xlsx
        └── output/
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

1. **Separated KAIST code from original package**
   - Original gcamreport code remains untouched
   - Easy to sync with upstream updates

2. **Shared configuration (`config.R`)**
   - Single file for all project settings
   - No need to edit multiple files when changing projects

3. **Organized output structure**
   - Each project gets its own folder under `projects/`
   - Template and mapping files at project root
   - Generated outputs in `output/` subfolder

## Quick Start

1. Edit `kaist/config.R` with your project settings
2. Follow prerequisites in `step1_generate_report.R`
3. Run scripts in order: step1 → step2 → step3 → step4 → step5

## References

- [Modify_Mapping_Template_Tutorial.Rmd](Modify_Mapping_Template_Tutorial.Rmd) - How to modify mappings
- [rgcam_patch.R](rgcam_patch.R) - Fix for BaseX 9.5+ compatibility
