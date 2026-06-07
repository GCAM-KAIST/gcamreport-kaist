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
│   ├── functions.R            # KAIST helpers + data overrides (patch_gcam_data)
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
   - Original gcamreport code in `R/`, `inst/`, and `data/` is untouched.
   - KAIST customizations live only in `kaist/`, so syncing with bc3LC
     upstream is conflict-free (see "Syncing with upstream" below).

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

## Syncing with upstream gcamreport

`R/`, `inst/`, and `data/` are kept byte-identical to upstream, so pulling the
latest gcamreport is conflict-free:

```
git fetch upstream
git merge upstream/gcam-core      # no conflicts -- all KAIST code is in kaist/
git push origin main
```

All KAIST customizations live in `kaist/`:

- **Custom functions** -> `kaist/functions.R`.
- **Data customizations** (the extra mapping rows and capacity-factor overrides
  that gcamreport needs for KAIST's GCAM runs -- `bio-ceiling`, `irnstl-ceiling`,
  `Gen_III_Korea`, Korea capacity factors, ...) are re-applied at runtime by
  `patch_gcam_data()` in `kaist/functions.R`. It is called at the top of step1
  and step2 (before `devtools::load_all`) and rewrites the built `data/*.rda`
  objects in place. The upstream `inst/extdata/saveDataFiles_*.R` is **never
  edited**, which is why merges never conflict.

## Moving to a new GCAM version (v8.2, v9, ...)

The applier (`patch_gcam_data`) stays the same; only the per-version values
change. To support a new version:

1. Set `version_number` in `kaist/config.R` (e.g. `"8.2"`).
2. Open `kaist/functions.R` and find the `kaist_overrides` list. It currently
   holds a single entry, `"v7.0" = list(...)`. **Add a sibling entry** keyed by
   the new GCAM_version string, right next to it:

   ```r
   kaist_overrides <- list(
     "v7.0" = list( ... ),    # existing -- leave as is
     "v8.2" = list( ... )     # <-- add this; copy the v7.0 block and adjust
   )
   ```

   Copy the whole `"v7.0"` block as a template and adjust the values (technology
   names, CF values, dropped `template` variables) for the new version. If a step
   errors on a missing/renamed column, check that version's mapping CSV column
   names.
3. Nothing else changes -- `patch_gcam_data("v8.2")` will pick up the new block
   automatically via the `paste0("v", version_number)` call in step1/step2.

## References

- [rgcam_patch.R](rgcam_patch.R) - Fix for BaseX 9.5+ compatibility
