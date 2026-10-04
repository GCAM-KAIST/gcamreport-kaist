# KAIST GCAM Reporting Workflow

## Overview

This folder contains the KAIST 6-step pipeline that turns GCAM output into
KMIP report tables and figures. The rest of
the repository is the original [bc3LC/gcamreport](https://github.com/bc3LC/gcamreport)
R package, used as-is.

## Folder Structure

```
gcamreport-kaist/
├── R/, inst/, data/           # Original gcamreport R package (untouched)
├── kaist/                     # KAIST custom scripts (this folder)
│   ├── README.md, ROADMAP.md  # This file; plan with phases, owners, dates
│   ├── docs/                  # Notes and bug analyses (local only, gitignored)
│   ├── core/                  # General use: make gcamreport run on any KAIST database
│   │   ├── config.R           # Shared configuration for all steps
│   │   ├── functions.R        # KAIST helpers + data overrides (patch_gcam_data)
│   │   ├── step1_generate_report.R
│   │   ├── rgcam_patch.R      # BaseX 9.5+ compatibility fix
│   │   ├── tools/             # step1_parallel.R (+ worker/merge), compare_outputs.R
│   │   ├── input/             # KAIST GCAM input XMLs for the name check (gitignored)
│   │   └── diagnostics/       # Ad-hoc reprex / check scripts (gitignored)
│   └── kmip/                  # KMIP submissions only
│       ├── step2_process_data.R   # Thin orchestrator -- calls modules/
│       ├── step3_create_mapping.R
│       ├── step4_fill_template.R
│       ├── step5_validate.R       # Pipeline-wide validation (checkpoints A-D)
│       ├── step6_plots.R          # Report figures (GHG pathway per scenario)
│       ├── compare_manual_report.qmd  # Manual-vs-auto comparison (optional)
│       ├── unit_table.R           # Unit conversions shared by step4 and step5
│       ├── modules/               # step2 adjustments, one file per adjustment
│       │   ├── 00_utils.R         # Shared utilities (year_cols, load_gcam_rda, ...)
│       │   ├── a1_...R ~ a6_...R  # Part A: all regions
│       │   ├── b1_...R ~ b6_...R  # Part B: Korea only
│       │   └── validate/          # step5 checkpoint functions + rule tables
│       ├── tools/test_step5.R     # step5 self-test (fault injection)
│       ├── steel/                 # KMIP2026 steel template tools (see steel/README.md)
│       └── data/                  # Coefficient files (L223, L225 CSVs)
└── (databases and outputs live outside the repo, see config.R db_path)
```

## Workflow Scripts

Paths are under `kaist/`. Run every script from the repo root.

| Step | Script | Purpose |
|------|--------|---------|
| 1 | `core/step1_generate_report.R` | Query GCAM database, generate base report |
| 2 | `kmip/step2_process_data.R` | Post-process data (CO2 prices, battery storage, Korea adjustments) |
| 3 | `kmip/step3_create_mapping.R` | Create variable mapping template |
| 4 | `kmip/step4_fill_template.R` | Apply mappings and unit conversions |
| 5 | `kmip/step5_validate.R` | Validate totals across all stages (see below) |
| 6 | `kmip/step6_plots.R` | Report figures from the step2 Korea csv (national GHG pathway in Mt CO2eq/yr, one line per scenario, gross/net LULUCF panels) |
| - | `kmip/compare_manual_report.qmd` | Manual-vs-auto comparison report; only useful when a hand-made reference workbook exists (KMIP2025) |

### Step 5: pipeline-wide validation

`Rscript kaist/kmip/step5_validate.R [--strict] [--checkpoints=A,B,C,D]`

Standalone; runnable after any stage (missing inputs are skipped). Checkpoints:

- **A** raw query sums from the `.dat` vs the step1 report, plus a list of
  query technologies/inputs absent from the mapping rdas (the silent-drop
  risk for new GCAM versions, e.g. SMRs in kaist9).
- **B** step1 vs step2 -- totals must be unchanged except the documented
  module adjustments (encoded in `modules/validate/v_tables.R`), plus
  conservation identities for b3 and b5.
- **C** parent variable = sum of children in the IAMC tree (catches
  double counting; known gaps are listed as SKIP with reasons).
- **D** independent recompute of the filled KMIP template vs step4 output.

Outputs: `step5_summary.csv`, `step5_mismatches.csv`, `step5_unmapped.csv`
in `output_dir`. Tolerances: `config.R` "Step5 validation" section.
Non-fatal by default; `--strict` errors when any check FAILs.
Checkpoint A needs the built `data/*_v<version>.rda` files -- if missing, run
`inst/extdata/saveDataFiles_GCAM<version>.R` then `patch_gcam_data()`.
Self-test: `Rscript kaist/kmip/tools/test_step5.R` (fault injection).

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

4. **step2 is a thin orchestrator over `kaist/kmip/modules/`**
   - Each adjustment is one function in one file (`a1` ~ `a6` run on all
     regions, `b1` ~ `b6` on Korea only). All functions are data in -> data out,
     so step2 reads as a list of calls and you can inspect `data` between them.
   - Module files only define functions; sourcing them executes nothing.
   - Ordering constraints: capacity-changing modules (a2, a3, a4) must run
     before a5 (parent-child consistency); inside a3 the nuclear addition must
     come before the renewable multiplier; Part B modules require the
     Korea-filtered data; b6 (steel process emissions) needs b3's Coal|Feedstock
     rows. Otherwise the b* order is arbitrary.
   - Values that are not queried from GCAM (Korea statistics, literature
     ratios, MT vehicle counts, ...) are catalogued in
     `kaist/docs/hardcoded_assumptions.md` -- a local-only note (`kaist/docs/`
     is gitignored); update it when you change one of those values.
   - To verify a refactor changed nothing:
     `source("kaist/core/tools/compare_outputs.R")` then
     `compare_csv(old_csv, new_csv)` (md5-based, prints first diffs).

## Quick Start

1. Open R in the repo root and run `devtools::load_all(".")` once to
   build the gcamreport package locally.
2. Edit `kaist/core/config.R`: set `run_name`, `db_name`, `target_region`,
   and the year range.
3. If BaseX 9.5+ is installed, source `kaist/core/rgcam_patch.R` once per
   session before step 1 (see the comment block in step1).
4. Run the steps in order from the repo root:
   `kaist/core/step1_generate_report.R` -> `kaist/kmip/step2_process_data.R` ->
   `kaist/kmip/step3_create_mapping.R` -> `kaist/kmip/step4_fill_template.R` ->
   `kaist/kmip/step5_validate.R` -> `kaist/kmip/step6_plots.R`. (Optional:
   `kaist/kmip/compare_manual_report.qmd` when a manual reference workbook exists.)
   `core/` is enough for general use (step1 only); `kmip/` is the KMIP pipeline.

### Parallel step1 (many scenarios)

Each BaseX query uses one CPU, so with several scenarios run one worker per
scenario instead of `step1_generate_report.R`:

```
Rscript kaist/core/tools/step1_parallel.R            # all scenarios in config.R
Rscript kaist/core/tools/step1_parallel.R --jobs=4   # at most 4 at a time
```

It patches the data once, starts `kaist/core/tools/step1_worker.R <scenario>`
per scenario (logs in `{output_dir}/logs/`), waits, then runs
`kaist/core/tools/step1_merge.R` to build the single `{run_name}.xlsx` and
`{run_name}_project_merged.dat` that step2 expects.

### Scenario manifest

The checked-in scenario names and database locations are declared in
`kaist-pj/scenario/config.R`. Run every declared scenario with:

```
Rscript kaist-pj/core/run_scenarios.R
```

Reports are written under `kaist-pj/scenario/reports_u0909/`. Add or change a
job in the manifest rather than editing the core runner.

## Syncing with upstream gcamreport

`R/`, `inst/`, and `data/` are kept byte-identical to upstream, so pulling the
latest gcamreport is conflict-free:

```
git fetch upstream
git merge upstream/gcam-core      # no conflicts -- all KAIST code is in kaist/
git push origin main
```

All KAIST customizations live in `kaist/`:

- **Custom functions** -> `kaist/core/functions.R`.
- **Data customizations** (the extra mapping rows and capacity-factor overrides
  that gcamreport needs for KAIST's GCAM runs -- `bio-ceiling`, `irnstl-ceiling`,
  `Gen_III_Korea`, Korea capacity factors, ...) are re-applied at runtime by
  `patch_gcam_data()` in `kaist/core/functions.R`. It is called at the top of step1
  and step2 (before `devtools::load_all`) and rewrites the built `data/*.rda`
  objects in place. The upstream `inst/extdata/saveDataFiles_*.R` is **never
  edited**, which is why merges never conflict.

## Moving to a new GCAM version (v8.2, v9, ...)

The applier (`patch_gcam_data`) stays the same; only the per-version values
change. To support a new version:

1. Set `version_number` in `kaist/core/config.R` (e.g. `"8.2"`).
2. Open `kaist/core/functions.R` and find the `kaist_overrides` list. It currently
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
