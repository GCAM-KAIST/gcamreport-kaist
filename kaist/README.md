<!-- [2026-10-04: Claude code] paths kaist/ -> kaist-pj/; new section "GCAM v9.1: KAIST u0909 scenarios" describing the replicated gcamreport-temp fixes; folder tree, output location, Testrun.R and step3/4/6 notes brought in line with the current files. -->

# KAIST GCAM Reporting Workflow

## Overview

This folder (`kaist-pj/`) contains the KAIST 6-step pipeline that turns GCAM
output into KMIP report tables and figures. The rest of the repository is the
[bc3LC/gcamreport](https://github.com/bc3LC/gcamreport) R package, used as-is
(`R/`, `inst/` and `data/` are synced from the `gcam-core` branch, which now
includes GCAM v9.1). The sibling folder `kaist/` is the KAIST team's original
script set from `GCAM-KAIST/gcamreport-kaist` `main` and is left untouched;
`kaist-pj/` is the personal working copy on branch `pj-kaist`.

## Folder Structure

```
gcamreport-kaist/
├── R/, inst/, data/           # gcamreport R package (synced from upstream, untouched)
├── kaist/                     # KAIST team scripts from GCAM-KAIST main (untouched)
├── kaist-pj/                  # Personal pipeline copy (this folder)
│   ├── README.md              # This file
│   ├── Testrun.R              # Run one step (or several) in a fresh Rscript with a log
│   ├── .gitignore             # Ignores scenario databases, .dat files and reports_u0909/
│   ├── core/                  # General use: make gcamreport run on any KAIST database
│   │   ├── config.R           # Shared configuration for all steps (reads scenario/config.R)
│   │   ├── functions.R        # KAIST helpers + data overrides (patch_gcam_data, kaist_overrides)
│   │   ├── gcamreport_patch.R # Runtime namespace patch (is_ignored guard, "fix 8")
│   │   ├── rgcam_patch.R      # BaseX 9.5+ compatibility fix
│   │   ├── step1_generate_report.R  # One generate_report() per manifest job + merge
│   │   ├── run_scenarios.R    # Minimal loop over the manifest (no merge, no step2 hand-off)
│   │   └── tools/             # step1_parallel.R (+ worker/merge), compare_outputs.R
│   ├── kmip/                  # KMIP submissions only
│   │   ├── step2_process_data.R   # Thin orchestrator -- calls modules/
│   │   ├── step3_create_mapping.R
│   │   ├── step4_fill_template.R
│   │   ├── step5_validate.R       # Pipeline-wide validation (checkpoints A-D)
│   │   ├── step6_plots.R          # Report figures (GHG pathway per scenario)
│   │   ├── compare_manual_report.qmd  # Manual-vs-auto comparison (optional)
│   │   ├── unit_table.R           # Unit conversions shared by step4 and step5
│   │   ├── modules/               # step2 adjustments, one file per adjustment
│   │   │   ├── 00_utils.R         # Shared utilities (year_cols, load_gcam_rda, ...)
│   │   │   ├── a1_...R ~ a6_...R  # Part A: all regions
│   │   │   ├── b1_...R ~ b6_...R  # Part B: Korea only
│   │   │   └── validate/          # step5 checkpoint functions + rule tables
│   │   ├── tools/test_step5.R     # step5 self-test (fault injection)
│   │   ├── steel/                 # KMIP2026 steel template tools (see steel/README.md)
│   │   └── data/                  # Coefficient files (L223, L225 CSVs)
│   ├── scenario/              # Scenario manifest and the u0909 inputs/outputs
│   │   ├── config.R           # scenario_jobs (db, scenario, label), version, output dir
│   │   ├── KAIST_9_Ref_u0909.xml, KAIST_9_NZ_u0909.xml   # GCAM configurations (reference)
│   │   ├── process_u0909.R    # Original two-scenario runner (superseded by core/)
│   │   ├── u0909r/, u0909n/   # BaseX databases, Ref and NZ (gitignored)
│   │   └── reports_u0909/     # output_dir: reports, csvs, .dat, logs/ (gitignored)
│   └── debug/                 # Copies of the gcamreport-temp debugging records
│       ├── ERROR_LOG.md       # First v9.1 mapping error, v9.1 vs v.9.1 key pitfall
│       └── case1_chemical_feedback_Sector/   # u0909 fixes 1-8: README, logs, BEFORE csvs
└── (the root .gitignore also hides data/*.rda and the team's kaist/docs, kaist/core/input)
```

Local-only notes that older versions of this README mentioned (`ROADMAP.md`,
`docs/hardcoded_assumptions.md`, `core/input/`, `core/diagnostics/`) are
gitignored and not present in this checkout.

**Git caveat.** The root `.gitignore` has the rule `kmip/` (meant for the GCAM
data folders), which matches `kaist-pj/kmip/` as well. As of 2026-10-04 nothing
under `kaist-pj/kmip/` (step2-6, `modules/`, `steel/`, `unit_table.R`) is
tracked by git; `git ls-files kaist-pj/kmip` is empty. Narrow the rule to
`/kmip/` (or add `!kaist-pj/kmip/`) before committing the pipeline.

## Workflow Scripts

Paths are under `kaist-pj/`. Run every script from the repo root (the
folder with `DESCRIPTION`), or use `Testrun.R` (below).

| Step | Script | Purpose |
|------|--------|---------|
| 1 | `core/step1_generate_report.R` | Query GCAM database, generate base report |
| 2 | `kmip/step2_process_data.R` | Post-process data (CO2 prices, battery storage, Korea adjustments) |
| 3 | `kmip/step3_create_mapping.R` | Create variable mapping template (`kmip_gcam_mapping_template.xlsx`) from the Korea csv and the KMIP template |
| 4 | `kmip/step4_fill_template.R` | Apply the reviewed mapping and unit conversions; writes `variables_before/after_unit_conversion.csv` |
| 5 | `kmip/step5_validate.R` | Validate totals across all stages (see below) |
| 6 | `kmip/step6_plots.R` | Report figures from the step2 Korea csv (national GHG pathway in Mt CO2eq/yr, one line per scenario, gross/net LULUCF panels) |
| - | `kmip/compare_manual_report.qmd` | Manual-vs-auto comparison report; only useful when a hand-made reference workbook exists (KMIP2025) |

Step 3 and step 4 read the KMIP template and the mapping workbook from
`template_path` and `mapping_path` in `core/config.R` (both default to
`output_dir`): `KMIP2025_DB_final.xlsx` must be copied there by hand, and the
mapping workbook is step 3's output after manual review. Step 3 uses `openxlsx`
only for column widths; if it is not installed the sheet is written with
`writexl` instead. Step 4 needs `readr`, `dplyr`, `tibble`, `tidyr`, `readxl`
(no `tidyverse` meta-package).

### Step 5: pipeline-wide validation

`Rscript kaist-pj/kmip/step5_validate.R [--strict] [--checkpoints=A,B,C,D]`

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
Self-test: `Rscript kaist-pj/kmip/tools/test_step5.R` (fault injection).

## Key Improvements

1. **Separated KAIST code from the original package**
   - Original gcamreport code in `R/`, `inst/`, and `data/` is untouched.
   - KAIST customizations live only in `kaist/`, so syncing with bc3LC
     upstream is conflict-free (see "Syncing with upstream" below).

2. **Shared configuration (`config.R`)**
   - One file for run name, database, region, and year range.
   - No need to edit multiple step scripts when changing the run.

3. **Per-run output folder**
   - `output_dir` comes from the scenario manifest
     (`scenario_output_dir` in `kaist-pj/scenario/config.R`, currently
     `kaist-pj/scenario/reports_u0909/`). Every step writes there, including
     the step1 `.dat` project files and the `logs/` of `Testrun.R`, so runs
     against different databases do not mix. Without a manifest the classic
     single-database layout applies.

4. **step2 is a thin orchestrator over `kaist-pj/kmip/modules/`**
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
     ratios, MT vehicle counts, ...) were catalogued in the team's local-only
     note `kaist/docs/hardcoded_assumptions.md` (gitignored, not in this
     checkout); the module headers carry the same information.
   - To verify a refactor changed nothing:
     `source("kaist-pj/core/tools/compare_outputs.R")` then
     `compare_csv(old_csv, new_csv)` (md5-based, prints first diffs).

## Quick Start

1. Open R in the repo root and run `devtools::load_all(".")` once to
   build the gcamreport package locally. The built `data/*_v9.1.rda` must
   exist (gitignored): run `inst/extdata/saveDataFiles_GCAM9.1.R` or copy
   them from an upstream checkout.
2. Check `kaist-pj/scenario/config.R` (databases, scenario names, labels,
   GCAM version, output folder) and `kaist-pj/core/config.R` (`run_name`,
   `target_region`, year range, step5/step6 options).
   `target_region` must be `"South Korea"` for step2 Part B, step3, step4 and
   step6; with `"All"` the Korea csv is written with a header only and step6
   stops with `object 'Emissions|Kyoto Gases' not found`.
3. If BaseX 9.5+ is installed, source `kaist-pj/core/rgcam_patch.R` once per
   session before step 1 (step1 and the step1 tools do this themselves).
4. Run the steps in order from the repo root:
   `kaist-pj/core/step1_generate_report.R` -> `kaist-pj/kmip/step2_process_data.R` ->
   `kaist-pj/kmip/step3_create_mapping.R` -> `kaist-pj/kmip/step4_fill_template.R` ->
   `kaist-pj/kmip/step5_validate.R` -> `kaist-pj/kmip/step6_plots.R`. (Optional:
   `kaist-pj/kmip/compare_manual_report.qmd` when a manual reference workbook exists.)
   `core/` is enough for general use (step1 only); `kmip/` is the KMIP pipeline.

### Test runs with `Testrun.R`

`kaist-pj/Testrun.R` runs any step in a fresh `Rscript` process (step1 and
step2 call `patch_gcam_data()` + `devtools::load_all()` and leave globals
behind, so a clean process per step is the reliable way to test one step):

```r
source("kaist-pj/Testrun.R")        # sets the working directory to the package root
run_step(1)                         # one step; stdout+stderr -> {output_dir}/logs/testrun_step1_*.log
run_step(5, args = "--checkpoints=A,B")
run_steps(2:6, stop_on_error = FALSE)   # several steps, summary table at the end
run_step(2, fresh = FALSE)          # source() in this session for interactive debugging
testrun_status()                    # which inputs / outputs of each step exist right now
```

The `TEST` block at the bottom of the file holds the calls that run when the
file is sourced; edit it to choose the steps. `testrun_status()` also warns
when `target_region` is `"All"`.

### Parallel step1 (many scenarios)

Each BaseX query uses one CPU, so with several scenarios run one worker per
scenario instead of `step1_generate_report.R`:

```
Rscript kaist-pj/core/tools/step1_parallel.R            # all scenarios in config.R
Rscript kaist-pj/core/tools/step1_parallel.R --jobs=4   # at most 4 at a time
```

It patches the data once, starts `kaist-pj/core/tools/step1_worker.R <scenario>`
per scenario (logs in `{output_dir}/logs/`), waits, then runs
`kaist-pj/core/tools/step1_merge.R` to build the single `{run_name}.xlsx` and
`{run_name}_project_merged.dat` that step2 expects.

### Scenario manifest

The checked-in scenario names and database locations are declared in
`kaist-pj/scenario/config.R`. Run every declared scenario with:

```
Rscript kaist-pj/core/run_scenarios.R
```

Reports are written under `kaist-pj/scenario/reports_u0909/`. Add or change a
job in the manifest rather than editing the core runner. `run_scenarios.R` is
the minimal loop (one `generate_report()` per job, no merge);
`step1_generate_report.R` does the same and then merges the per-job reports and
`.dat` files into the single `{run_name}.*` set that step2 expects, so prefer
step1 for the KMIP pipeline. `scenario/process_u0909.R` is the first version of
that loop, kept for reference.

## Syncing with upstream gcamreport

`R/`, `inst/`, and `data/` are kept byte-identical to upstream, so pulling the
latest gcamreport is conflict-free:

```
git fetch upstream
git merge upstream/gcam-core      # no conflicts -- all KAIST code is in kaist/ and kaist-pj/
git push origin pj-kaist
```

(In this checkout `upstream` points at GCAM-KAIST with pushing disabled; the
package folders were last synced with the commit "Sync shared folders from
gcamreport core".) All KAIST customizations live in `kaist-pj/`:

- **Custom functions** -> `kaist-pj/core/functions.R`.
- **Data customizations** (the extra mapping rows and capacity-factor overrides
  that gcamreport needs for KAIST's GCAM runs -- `bio-ceiling`, `irnstl-ceiling`,
  `Gen_III_Korea`, Korea capacity factors, ...) are re-applied at runtime by
  `patch_gcam_data()` in `kaist-pj/core/functions.R`. It is called at the top of step1
  and step2 (before `devtools::load_all`) and rewrites the built `data/*.rda`
  objects in place. The upstream `inst/extdata/saveDataFiles_*.R` is **never
  edited**, which is why merges never conflict.

## Moving to a new GCAM version (v8.2, v9, ...)

The applier (`patch_gcam_data`) stays the same; only the per-version values
change. To support a new version:

1. Set `version_number` in `kaist-pj/core/config.R` (e.g. `"8.2"`).
2. Open `kaist-pj/core/functions.R` and find the `kaist_overrides` list. It
   holds one entry per version (`"v7.0"`, `"v9.1"`). **Add a sibling entry** keyed by
   the new GCAM_version string, right next to them:

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
   Every applier step (cf tables, capital, template, ...) runs only when the
   block defines its spec, so a minimal block with just `map_rows` is valid.

## GCAM v9.1: KAIST u0909 scenarios

The `"v9.1"` block of `kaist_overrides` and `kaist-pj/core/gcamreport_patch.R`
replicate the fixes that were worked out in the scratch checkout
`gcamreport-temp` for the two KAIST v9.1 scenarios (`KAIST_9_Ref_u0909`,
`KAIST_9_NZ_u0909`). The full debugging record is
`gcamreport-temp/debug/case1_chemical_feedback_Sector/Error_Log/README.md`
(a copy lives under `kaist-pj/debug/`). In `gcamreport-temp` the fixes were made
by editing `inst/extdata/mappings/GCAM9.1/*.csv` and `R/functions.R` and
rebuilding the rdas; here `R/`, `inst/` and `data/` stay upstream and the same
changes are re-applied at runtime:

| fix | upstream object | what the KAIST run needed | replicated by |
|---|---|---|---|
| 1 | `carbon_seq_tech_map_v9.1` | rows for `chemical feedstocks` x `gas` / `coal` (KAIST feedstock techs report feedstock carbon as sequestration) | `kaist_overrides$v9.1$map_rows` |
| 2, 4 | `energy_price_map_v9.1` | KAIST-only markets -> `NoReported`: `bio-ceiling`, `rowbio-ceiling`, `cement-ceiling`, `coal-ceiling`, `imported H2`, `dac-ceiling`, `CO2_Kor`, `rowCO2`, `rowCO2_LUC` | `map_rows` |
| 3, 5 | `primary_energy_map_v9.1` | `uranium` -> `Primary Energy`, `Primary Energy\|Nuclear`; `bio-ceiling`, `bio-ceiling CCS`, `coal-ceiling`, `cement-ceiling` -> `NoReported` | `map_rows` |
| 6 | `co2_market_v9.1` | `rowCO2` -> every region except South Korea (otherwise `Price\|Carbon` is 0 outside Korea) | `table_rows` |
| 7 | `ag_demand_map_v9.1` | `bio-ceiling` / `regional biomass` -> `NoReported` (replaces `ignore = "^bio-ceiling$"`) | `ag_demand_rows` |
| 8 | `R/functions.R::get_co2_price_fragmented_tmp()` | with `ignore = NULL`, `grepl("", market)` dropped every CO2 price market -> all carbon prices 0 | `gcamreport_patch.R` rewrites the two filters to `is_ignored()` inside the loaded namespace |

Everything else that differs between `gcamreport-temp` and upstream
(`CO2_tech_map` biomass rows, `hdd_cdd`, template and `var_fun_map` edits, the
`do_bind_results()` tier-1 change, removal of the `food demand v2` queries) is
upstream moving on after the temp snapshot, not a KAIST fix, and is deliberately
not replicated.

Step 1 for these scenarios: `kaist-pj/scenario/config.R` declares one job per
database; `step1_generate_report.R` runs `generate_report()` once per job, writes
`{run_name}_{label}.*` plus its `.dat`, and then merges them into `{run_name}.*`
and `{run_name}_project_merged.dat` for step2. `data/*.rda` must exist first
(gitignored; build with `inst/extdata/saveDataFiles_GCAM9.1.R` or copy from an
upstream checkout); `patch_gcam_data("v9.1")` then adds the rows above.

## References

- [core/rgcam_patch.R](core/rgcam_patch.R) - Fix for BaseX 9.5+ compatibility
- [core/gcamreport_patch.R](core/gcamreport_patch.R) - Runtime patch for the empty-`ignore` CO2 price bug
- [debug/case1_chemical_feedback_Sector/Error_Log/README.md](debug/case1_chemical_feedback_Sector/Error_Log/README.md) - Full record of the u0909 fixes 1-8
- [kmip/steel/README.md](kmip/steel/README.md) - Steel template tools
