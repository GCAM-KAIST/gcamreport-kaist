# KAIST GCAM Reporting Workflow

## Overview

This folder contains the KAIST 7-step pipeline that turns GCAM output into KMIP report tables, figures and a comparison report. The rest of the repository is the [bc3LC/gcamreport](https://github.com/bc3LC/gcamreport) R package, taken from the branch `kaist/v9.1-korea` (upstream `gcam-core` plus our package fixes).

Branches:

- `main`: package code from `kaist/v9.1-korea` plus this `kaist/` folder. Use this one. `data/` is tracked, so a fresh clone runs without building data.
- `kaist/v9.1-korea`: package only (no `kaist/` folder). Fixes to `R/`, `inst/`, `data/` go here, one topic per commit, through a PR to this branch. It is then merged into `main`, and single commits can be sent upstream to bc3LC.
- `fix/...`: branches of open upstream PRs (for example PR #94).

## Folder Structure

```
gcamreport-kaist/
├── R/, inst/, data/           # gcamreport package, from branch kaist/v9.1-korea (do not edit on main)
├── kaist/                     # KAIST custom scripts (this folder)
│   ├── README.md, ROADMAP.md  # This file; plan with phases, owners, dates
│   ├── docs/                  # Notes and bug analyses (local only, gitignored)
│   ├── core/                  # General use: make gcamreport run on any KAIST database
│   │   ├── config.R           # Loader: reads the settings file named by KAIST_CONFIG, sets derived paths
│   │   ├── functions.R        # KAIST helpers + data overrides (patch_gcam_data)
│   │   ├── step1_generate_report.R
│   │   ├── rgcam_patch.R      # BaseX 9.5+ compatibility fix
│   │   ├── queries/           # Extra queries added to every step1 project (kaist_queries.xml)
│   │   ├── tools/             # step1_parallel.R (+ worker/merge), merge_basex_dbs.R (scenarios of several DBs -> one DB), compare_outputs.R
│   │   ├── input/             # KAIST GCAM input XMLs for the name check (gitignored)
│   │   └── diagnostics/       # Ad-hoc reprex / check scripts (gitignored)
│   ├── ktraces/               # K-TRACES tables only (not IAMC-standard variables)
│   │   ├── config/            # Run settings (ssp2_ndc.R)
│   │   ├── functions.R        # K-TRACES data overrides (patch_project_data, applied by the core step1 hook)
│   │   ├── build_ktraces_workbook.R  # Merged step1 report -> K-TRACES workbook (South Korea, USD_2025)
│   │   └── data/              # USD deflator csv (FRED A191RD3A086NBEA)
│   └── kmip/                  # KMIP submissions only
│       ├── config/                # Run settings, one file per run (kaist9_hlm.R, nmsf2.R)
│       ├── step2_process_data.R   # Thin orchestrator -- calls modules/
│       ├── step3_create_mapping.R
│       ├── step4_fill_template.R
│       ├── step5_validate.R       # Pipeline-wide validation (checkpoints A-D)
│       ├── step6_plots.R          # Report figures (GHG pathway per scenario)
│       ├── step7_compare.R/.qmd   # Comparison report (PDF) against a reference run, e.g. the KMIP2025 submission
│       ├── run_pipeline.sh        # Steps 1-7 in one command
│       ├── write_submission.py    # Called by step4: KMIP submission workbook (Python + openpyxl)
│       ├── template/              # KMIP template, submission layout and mapping (variable names only, no values)
│       ├── unit_table.R           # Unit conversions shared by step4 and step5
│       ├── modules/               # step2 adjustments, one file per adjustment
│       │   ├── 00_utils.R         # Shared utilities (year_cols, load_gcam_rda, ...)
│       │   ├── a1_...R ~ a6_...R  # Part A: all regions
│       │   ├── b1_...R ~ b8_...R  # Part B: Korea only
│       │   └── validate/          # step5 checkpoint functions + rule tables
│       ├── tools/test_step5.R     # step5 self-test (fault injection)
│       ├── steel/                 # KMIP2026 steel template tools (see steel/README.md)
│       └── data/                  # Coefficient files (L223, L225 CSVs)
│   └── scenario/              # Scenario XMLs and notes of test runs (input/<run>/, RESULT.md)
└── (databases and outputs live outside the repo, see db_path in the settings file; never commit result files)
```

## Workflow Scripts

Paths are under `kaist/`. Run every script from the repo root.

| Step | Script | Purpose |
|------|--------|---------|
| 1 | `core/step1_generate_report.R` | Query GCAM database, generate base report |
| 2 | `kmip/step2_process_data.R` | Post-process data (CO2 prices, battery storage, Korea adjustments) |
| 3 | `kmip/step3_create_mapping.R` | Create variable mapping template |
| 4 | `kmip/step4_fill_template.R` | Apply mappings and unit conversions; write `{run_name}_KMIP_submission.xlsx` in the submitted KMIP layout (Python + openpyxl, `KAIST_PYTHON`) |
| 5 | `kmip/step5_validate.R` | Validate totals across all stages (see below) |
| 6 | `kmip/step6_plots.R` | Report figures from the step2 Korea csv (national GHG pathway in Mt CO2eq/yr, one line per scenario, gross/net LULUCF panels) |
| 7 | `kmip/step7_compare.R` + `kmip/step7_compare.qmd` | Comparison report (PDF) against a reference run (the KMIP2025 submission workbook or a step4 csv of an earlier run): all scenarios side by side, then one scenario pair variable by variable. Needs quarto and the `compare_*` block in the settings file |
| - | `core/tools/step1_worker.R` with `ktraces/config/ssp2_ndc.R`, then `ktraces/build_ktraces_workbook.R` | K-TRACES: step1 with the Construction / Mining / service-output extensions (`patch_project_data()` in `ktraces/functions.R`, picked up by the step1 project hook; one worker per scenario, then `core/tools/step1_merge.R`), then the K-TRACES workbook. Not for KMIP / IAMC submissions |

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
in `output_dir`. Tolerances: "Step5 validation" section of the settings file.
Non-fatal by default; `--strict` errors when any check FAILs.
Checkpoint A needs the built `data/*_v<version>.rda` files -- if missing, run
`inst/extdata/saveDataFiles_GCAM<version>.R` (KAIST rows are added in memory by `load_gcam_rda()`).
Self-test: `Rscript kaist/kmip/tools/test_step5.R` (fault injection).

## Key Improvements

1. **Separated KAIST code from the package**
   - On `main`, `R/`, `inst/` and `data/` are never edited by hand; they come from the branch `kaist/v9.1-korea`.
   - KAIST customizations live only in `kaist/` (see "Syncing with upstream" below).

2. **Run settings per project (`KAIST_CONFIG`)**
   - Each run has one settings file (run name, database, region, years, scenarios) in its project folder, e.g. `kaist/kmip/config/kaist9_hlm.R`. Projects never edit each other's settings.
   - `kaist/core/config.R` is only a loader: every step sources it, it reads the file named by the `KAIST_CONFIG` environment variable and stops with a list of available files if it is not set.

3. **Per-database output folder**
   - Outputs are written under `kmip/{db_name}_output/`, so different
     databases (DB25, DB26, ...) do not mix. A settings file may set
     `output_dir` itself; the `kaist/scenario/` test runs use
     `kaist/scenario/output/{run_name}` (see `kaist/scenario/RESULT.md`).

4. **step2 is a thin orchestrator over `kaist/kmip/modules/`**
   - Each adjustment is one function in one file (`a1` ~ `a6` run on all
     regions, `b1` ~ `b8` on Korea only). All functions are data in -> data out,
     so step2 reads as a list of calls and you can inspect `data` between them.
   - Module files only define functions; sourcing them executes nothing.
   - Ordering constraints: capacity-changing modules (a2, a3, a4) must run
     before a5 (parent-child consistency); inside a3 the nuclear addition must
     come before the renewable multiplier; Part B modules require the
     Korea-filtered data; b6 (steel process emissions) needs b3's Coal|Feedstock
     rows; b7 (hybrid Energy Service rows) must run before b4 (vehicle conversion). Otherwise the b* order is arbitrary.
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
2. Pick or create a settings file in your project folder (copy `kaist/kmip/config/kaist9_low26.R`; set `run_name`, `db_path`, `db_name`, `scenarios`, years and the `compare_*` block) and point `KAIST_CONFIG` to it: `KAIST_CONFIG=kaist/kmip/config/kaist9_low26.R Rscript kaist/kmip/step4_fill_template.R`, or `Sys.setenv(KAIST_CONFIG = "...")` in RStudio. One GCAM database per scenario (gcam-kaist9): merge them into one database first, see below.
   Step4 also writes `{run_name}_KMIP_submission.xlsx`; it needs Python with pandas and openpyxl (set `KAIST_PYTHON` if `python3` lacks them).
3. If BaseX 9.5+ is installed, source `kaist/core/rgcam_patch.R` once per
   session before step 1 (see the comment block in step1).
4. Run everything with `kaist/kmip/run_pipeline.sh kaist/kmip/config/<run>.R`: step1 with one worker per scenario, then steps 2, 4, 5, 6 and 7 (logs in `{output_dir}/logs/<date>/`; `--from 2` skips step1). Or run the steps by hand in that order from the repo root; step3 (`kaist/kmip/step3_create_mapping.R`) only when the template or the mapping changes.
   `core/` is enough for general use (step1 only); `kmip/` is the KMIP pipeline;
   `ktraces/` builds the K-TRACES workbook from a step1 run made with its settings file.

### Parallel step1 (many scenarios)

Each BaseX query uses one CPU, so with several scenarios run one worker per
scenario instead of `step1_generate_report.R`:

```
Rscript kaist/core/tools/step1_parallel.R            # all scenarios in the KAIST_CONFIG settings file
Rscript kaist/core/tools/step1_parallel.R --jobs=4   # at most 4 at a time
```

It patches the data once, starts `kaist/core/tools/step1_worker.R <scenario>`
per scenario (logs in `{output_dir}/logs/`), waits, then runs
`kaist/core/tools/step1_merge.R` to build the single `{run_name}.xlsx` and
`{run_name}_project_merged.dat` that step2 expects.

### One database per scenario (gcam-kaist9): merge first

gcam-kaist9 writes one BaseX database per run (e.g. `kmip/KAIST9_LOW26/low_nz/`). Merge the scenarios you want into one database; the settings file then points at that database like any other (`db_path`, `db_name`, `scenarios`):

```
Rscript kaist/core/tools/merge_basex_dbs.R list kmip/KAIST9_LOW26        # scenarios in every database of the folder
Rscript kaist/core/tools/merge_basex_dbs.R merge kmip/KMIP26_LOW kmip/KAIST9_LOW26/low_ref kmip/KAIST9_LOW26/low_nz
```

`merge` copies the scenario documents with the BaseX jar (no ModelInterface, no export file); `<db folder>:<scenario name>` picks one scenario of a database. The report keeps the GCAM scenario names; `scenario_labels <- c("KAIST_9_NZ_u1007low" = "low_nz", ...)` in the settings file renames them in the merged step1 outputs (then `scenarios` lists the GCAM names and everything after step1 uses the labels).

### Step 7: comparison with a reference run

`compare_a_file` in the settings file names the reference: the KMIP2025 submission workbook (sheet `data`, `compare_a_model`) or a step4 csv of an earlier run. `compare_pair` picks the scenario pair for the variable-by-variable part, `compare_a_scenarios` / `compare_b_scenarios` the lines of the overview, and `compare_ref_step2_csv` (optional) a step2 Korea csv of the reference database for the national gross/net GHG panel. Output: `{output_dir}/compare/{run_name}_compare.pdf` plus one png and csv per section. Quarto must be on PATH or in `QUARTO_BIN`.

## Syncing with upstream gcamreport

Upstream changes come in through `kaist/v9.1-korea`, never directly into `main` (do not use the GitHub "Sync fork" button: it merges upstream into `main`). `kaist/v9.1-korea` is protected, so the upstream merge goes through a PR:

```
git fetch upstream
git checkout -b sync/upstream-<date> origin/kaist/v9.1-korea
git merge upstream/main           # bc3LC renamed gcam-core to main (2026-10-21)
git push -u origin sync/upstream-<date>
# open a PR to kaist/v9.1-korea
```

Every day the workflow `.github/workflows/kaist_branch_to_main.yaml` opens a PR "kaist/v9.1-korea -> main" when the package branch has commits that `main` does not have, and merges it with a merge commit (main is protected: changes only through PRs, except jiheunha). `kaist/` is never touched by this merge. If the PR cannot be merged it stays open; then merge by hand. The workflow can also be started from the Actions tab (Run workflow).

To send one of our package fixes upstream, cherry-pick its commit onto a new branch from `upstream/main` and open the PR from there.

All KAIST customizations live in `kaist/`:

- **Custom functions** -> `kaist/core/functions.R`.
- **Data customizations** (the extra mapping rows and capacity-factor overrides
  that gcamreport needs for KAIST's GCAM runs -- `bio-ceiling`, `irnstl-ceiling`,
  `Gen_III_Korea`, Korea capacity factors, ...) are re-applied at runtime by
  `patch_gcam_data()` in `kaist/core/functions.R`. It is called in step1 and step2
  right after `devtools::load_all` and changes the loaded data objects in memory
  only; the tracked `data/*.rda` files are never written. Step2/step5 helpers get
  the patched objects through `load_gcam_rda()`.

## Moving to a new GCAM version (v8.2, v9, ...)

The applier (`patch_gcam_data`) stays the same; only the per-version values
change. To support a new version:

1. Set `version_number` in your settings file (e.g. `"8.2"`).
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
