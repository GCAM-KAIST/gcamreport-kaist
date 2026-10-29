# KAIST GCAM reporting workflow

## Overview

This folder holds the KAIST pipeline that turns GCAM output into KMIP report tables, a GHG pathway figure and a comparison report, in five steps. The rest of the repository is the [bc3LC/gcamreport](https://github.com/bc3LC/gcamreport) R package, taken from the branch `kaist/v9.1-korea` (upstream `main` plus our package fixes).

Branches:

- `main`: package code from `kaist/v9.1-korea` plus this `kaist/` folder. Use this one. `data/` is tracked, so a fresh clone runs without building data.
- `kaist/v9.1-korea`: package only (no `kaist/` folder). Fixes to `R/`, `inst/`, `data/` go here, one topic per commit, through a PR to this branch. It is then merged into `main`, and single commits can be sent upstream to bc3LC.
- `fix/...`: branches of open upstream PRs (for example PR #94).

## Folder structure

```
gcamreport-kaist/
├── R/, inst/, data/           # gcamreport package, from branch kaist/v9.1-korea (do not edit on main)
├── kaist/                     # KAIST custom scripts (this folder)
│   ├── README.md              # This file
│   ├── core/                  # General use: make gcamreport run on any KAIST database
│   │   ├── config.R           # Loader: reads the config file named by KAIST_CONFIG, sets derived paths
│   │   ├── functions.R        # KAIST helpers + data overrides (patch_gcam_data, kaist_overrides)
│   │   ├── step1_generate_report.R
│   │   ├── rgcam_patch.R      # BaseX 9.5+ compatibility fix
│   │   └── tools/             # step1_parallel.R (+ worker/merge), merge_basex_dbs.R (scenarios of several DBs -> one DB), compare_outputs.R
│   ├── ktraces/               # K-TRACES tables only (not IAMC-standard variables)
│   │   ├── config/            # Run settings (ssp2_ndc.R)
│   │   ├── functions.R        # K-TRACES data overrides (patch_project_data, applied by the core step1 hook)
│   │   ├── build_ktraces_workbook.R  # Merged step1 report -> K-TRACES workbook (South Korea, USD_2025)
│   │   └── data/              # USD deflator csv (FRED A191RD3A086NBEA)
│   └── kmip/                  # KMIP submissions only
│       ├── config/                # Run settings, one file per run (kaist9_low26.R, kaist9_hlm.R, nmsf2_k9l.R)
│       ├── step2_adjust.R         # Korea adjustments, one module per rule (modules/)
│       ├── step3_template.R       # Mapping + unit conversion -> filled KMIP template + submission workbook
│       ├── step4_check.R          # Pipeline-wide validation (checkpoints A-D, modules/validate/)
│       ├── step5_report.R/.qmd    # GHG pathway figure + comparison report (PDF) against a reference run
│       ├── run_pipeline.sh        # Steps 1-5 in one command
│       ├── functions.R            # KMIP-only data overrides (NMSF2 gas markets), applied by the step1 project hook
│       ├── make_mapping.R         # Build the variable mapping (only when the template or the mapping changes)
│       ├── data/                  # Inputs that are not GCAM output: KMIP template, submission layout and mapping
│       │                          #   (variable names only, no values), coefficient csvs (L223, L225 from the
│       │                          #   GCAM 9.1 xml), extra queries (nmsf2_queries.xml, named by project_queries)
│       ├── modules/               # Code used by steps 2-4
│       │   ├── 00_utils.R, unit_table.R   # Shared helpers; unit conversions used by step3 and step4
│       │   ├── a1_...R ~ a6_...R  # step2 part A: all regions
│       │   ├── b1_...R ~ b9_...R  # step2 part B: Korea only
│       │   └── validate/          # step4 checkpoints, rule tables and test_check.R
│       └── steel/                 # KMIP2026 steel sheet tools (see steel/README.md)
└── (databases, outputs, notes and GCAM input XMLs live outside the repo, see db_path in the config file; never commit result files)
```

## The five steps

Paths are under `kaist/`. Run every script from the repo root. `kmip/run_pipeline.sh <settings>`
runs them in order and stops at the first step whose R process exits with an error; a step
"passes" the pipeline when its script finishes (exit 0) and writes the outputs listed below.
Step 4 is the only step that judges the numbers: it never stops the pipeline unless
`check_strict <- TRUE` (or `--strict`) is set.

| Step | Script | What it does | Outputs in `output_dir` | Passes when |
|------|--------|--------------|-------------------------|-------------|
| 1 | `core/step1_generate_report.R`, or `core/tools/step1_parallel.R` with one worker per scenario (what `run_pipeline.sh` uses) | Loads the package with `devtools::load_all`, applies the KAIST data overrides in memory (`patch_gcam_data`), queries each BaseX database with `generate_report()` (all IAMC variables, all regions, policy markets in `ignore_markets` dropped from the price rows), then `step1_merge.R` row-binds the per-scenario reports and merges the rgcam projects into one `.dat` (scenario names relabelled if `scenario_labels` is set) | `{run_name}_{label}.xlsx/.csv/.RData` and `{run_name}_{label}_project.dat` per scenario; merged `{run_name}.xlsx`, `{run_name}.csv`, `{run_name}_project_merged.dat`; `logs/step1_{scenario}.log` | Every worker exits 0 (the `.dat` holds every query and `Database scenarios:` lists the requested scenario), gcamreport's vetting prints `Inf variables: OK` and `NA variables: OK`, the merge reports the expected number of scenarios, and no `policy-like markets not in ignore_markets` warning appears |
| 2 | `kmip/step2_adjust.R` | Reads `{run_name}.xlsx` and the merged `.dat`, then runs the modules in `kmip/modules/` in order. Part A, all regions: a1 `Price\|Carbon` from the CO2 prices query, a2 battery storage capacity, a3 Gen_III_Korea nuclear into `Primary Energy\|Nuclear` plus the 2.1x direct-equivalent factor for renewables, a4 capacity recalculated from vintages with GCAM capacity factors, a5 parent capacity sums, a6 HVC unit relabel. Part B, Korea only: b1 international bunkers removed from the emission totals (years >= 2020), b2 primary energy for hydrogen and biomass electricity, b3 steel coal into Fuel/Feedstock, b7 hybrid-vehicle rows, b4 energy service to thousand vehicles (MT 2020 ratio anchored on `ref_scenario`), b5 biomass share of every `...\|Liquids` row, b6 steel process emissions, b8 geological CCS, b9 LULUCF inventory adjustment (only when the DB has `CO2_LULUCF_adj`) | `{run_name}.csv` (all regions), `{run_name}_korea.csv`, `gcam_available_variables.csv` | Script exits 0 and prints `=== Step 2 Complete ===`. A module prints `Skipped ...` when its query or variable is absent; that is informational, but each skip must be explainable (b9 skips on every run without the LULUCF gas). The arithmetic itself is verified by checkpoint B |
| 3 | `kmip/step3_template.R` | Maps the Korea csv onto the KMIP template with `kmip/data/kmip_gcam_mapping_template.xlsx` (base variable plus add/subtract columns), converts units with `kmip/modules/unit_table.R`, fills every template row for every scenario (unmapped rows stay empty), prints a coverage report (Required / Optional rows from the template) and writes the submission workbook in the submitted layout (openxlsx, cell styles copied from `KMIP2025_DB_template_submission.xlsx`) | `variables_before_unit_conversion.csv`, `variables_after_unit_conversion.csv`, `{run_name}_KMIP_submission.xlsx` | Script exits 0, every unit in the mapping is known to the unit table, the coverage report prints for every scenario, and the submission workbook lists all scenarios. Coverage below 100 % is a mapping gap, not a failure; the template rows that stay empty are the ones to review in `make_mapping.R` |
| 4 | `kmip/step4_check.R` | Pipeline-wide validation, checkpoints A to D (see below) | `check_summary.csv` (one row per check), `check_mismatches.csv` (every failing cell), `check_unmapped.csv` | All checks PASS, or only the documented WARN / FAIL cases listed under "Step 4: check" below. Anything else is a real defect |
| 5 | `kmip/step5_report.R` + `kmip/step5_report.qmd` | National GHG pathway figure from `Emissions\|Kyoto Gases` (net, and gross = net minus LULUCF when `plot_measures` includes "Gross") in the Korea csv, one line per scenario, with optional target and cap points. With `compare_a_file` set: the comparison report against a reference run, rendered with quarto to PDF | `{run_name}_ghg_pathway.png`, `{run_name}_ghg_pathway.csv`; with a reference run also `compare/{run_name}_compare.pdf` plus one png and csv per section | Figure and csv written with one series per scenario (the script prints `=== Step 5 Complete ===`); without `compare_a_file` it prints `comparison report skipped`. With a reference run, quarto must exit 0 and the PDF must exist |
| - | `kmip/make_mapping.R` | Build the variable mapping template from a step2 output. Needed only when the KMIP template or the mapping changes; one manual review pass | | |
| - | `core/tools/step1_worker.R` with `ktraces/config/ssp2_ndc.R`, then `ktraces/build_ktraces_workbook.R` | K-TRACES: step1 with the Construction / Mining / service-output extensions (`patch_project_data()` in `ktraces/functions.R`, picked up by the step1 project hook; one worker per scenario, then `core/tools/step1_merge.R`), then the K-TRACES workbook. Not for KMIP / IAMC submissions | | |

### Step 4: check

`Rscript kaist/kmip/step4_check.R [--strict] [--checkpoints=A,B,C,D]`

Step4 runs in every pipeline run (`run_pipeline.sh` calls it after step3). It can also run alone after any stage; inputs that do not exist yet are skipped. `step4_check.R` itself only reads the settings and prints the summary. The checks are the files in `kmip/modules/validate/`: `v0_engine.R` compares two tables with tolerances, decides PASS, WARN or FAIL and writes the reports; `v1` to `v4` hold one checkpoint each; `v_tables.R` holds the rule tables (which module may change which variable, parent-child relations, known gaps). `test_check.R` in the same folder tests the checker itself: it damages copies of the outputs and asserts that each checkpoint notices. It is not part of a pipeline run.

Status per check: **PASS** = every compared cell is within the tolerance (`rel_diff = |a-b| / max(|a|,|b|,1e-12)` <= `check_tol_rel_*` from the settings); **WARN** = nothing is wrong numerically but something is missing (a module left no rows, a template row could not be filled, a query key is marked NoReported); **FAIL** = at least one cell outside the tolerance, a lost or unexpected row, or a query key the mapping does not know; **SKIP** = input missing or a documented gap that is listed on purpose. The checkpoint status is the worst status of its checks. Checkpoints:

- **A, raw vs step1** (`v1_checkpoint_a.R`, tolerance `check_tol_rel_a`, 1e-2 by default). Recomputes report
  totals directly from the rgcam queries in the merged `.dat` and compares them with the step1 report,
  per scenario, region and year. Six aggregates (`v_tables.R::check_registry`): `fe_nontrn` (final energy
  by sector and fuel, non-transport), `fe_transport`, `se_elec` (electricity generation) and `co2_total`
  (`CO2 emissions by region` x 3.667 vs `Emissions|CO2|Energy and Industrial Processes`, checked up to 2035
  only) compare sums; `fe_nontrn`, `fe_transport`, `se_elec`, `co2_tech` and `co2_resource` also check
  coverage: every sector/technology/input key in the query must exist in the mapping rda of this GCAM
  version. `:sum` checks PASS when all cells are within tolerance and FAIL otherwise; `:coverage` checks
  FAIL on a key absent from the mapping (gcamreport drops such rows silently), WARN when the only findings
  are keys the mapping marks `NoReported` on purpose, PASS when every key is mapped. A query missing from
  the `.dat` gives SKIP. The findings go to `check_unmapped.csv`.
- **B, step1 vs step2** (`v2_checkpoint_b.R`, tolerance `check_tol_rel_b`, 1e-6). B1 compares the step1
  report with the step2 all-regions csv, B2 the Korea rows of that csv with the Korea csv. Every variable
  that no rule in `check_exceptions` names must pass through unchanged: `pass_through` PASSes when no row
  is lost, no row appears and no value moves; `unit_only` additionally allows a unit relabel (a6). For each
  module rule with `verify = "exists"` the module's output rows must be present (PASS) or the check WARNs
  that the module may not have run. Three identities must hold to the tolerance: b3 Coal|Fuel +
  Coal|Feedstock = Solids|Coal, b5 scaled Liquids + Biomass|Liquids = original Liquids for every sector,
  b6 steel energy CO2 + process CO2 = original steel CO2. B is the check that the step2 arithmetic did
  exactly what its documentation says and nothing else.
- **C, tree sums** (`v3_checkpoint_c.R`, tolerance `check_tol_rel_c`, 1e-6). For each relation in
  `check_relations` (final energy by fuel and by sector, residential + commercial, industry fuels,
  electricity by source, fossil and non-biomass renewable subtotals, CO2 top level and E&IP, capacity
  w/ and w/o CCS, PV + CSP, onshore + offshore) the parent must equal the sum of its children in the
  step1 report, the step2 all-regions csv and the Korea csv; a missing child counts as 0. PASS when every
  cell is within tolerance. Relations that are known not to hold (`check_known_violations`: capacity grand
  total, primary energy total after a3/b2, battery storage, step1 capacity parents, b5 industry share) are
  printed as SKIP with their reason and are never asserted.
- **D, template fill** (`v4_checkpoint_d.R`, tolerance `check_tol_rel_d`, 1e-6). Recomputes the filled
  template from the Korea csv, the mapping and the unit table with its own code and compares it with
  `variables_after_unit_conversion.csv`. Each template row x scenario x year is classified: `ok`
  (match), `expected_missing` (template row without mapping, empty on both sides), `lost_row` (mapped,
  but the base variable is not in the Korea csv), `unit_unconverted`, `value_mismatch`, `unexpected_missing`
  (recompute has a value, step3 does not) and `unexpected_value` (step3 has a value without a mapping).
  FAIL on any of the last three, WARN when there are only `lost_row` / `unit_unconverted` rows, PASS otherwise.

Outputs: `check_summary.csv`, `check_mismatches.csv`, `check_unmapped.csv`
in `output_dir`. Tolerances: "Step4 check" section of the config file.
Non-fatal by default; `--strict` errors when any check FAILs.
Checkpoint A needs the built `data/*_v<version>.rda` files; if they are missing, run
`inst/extdata/saveDataFiles_GCAM<version>.R` (KAIST rows are added in memory by `load_gcam_rda()`).
Self-test: `Rscript kaist/kmip/modules/validate/test_check.R` (fault injection).

Documented non-PASS results that every gcam-kaist9 run shows today (not defects):

- A `co2_total:sum` FAIL: in 2035 the regional CO2 sum and `Emissions|CO2|Energy and Industrial
  Processes` differ by 1-2 % for one or two South American regions in the policy scenarios
  (upstream negative-emissions accounting; the upstream gcamreport test has the same gap). South Korea passes.
- A `fe_nontrn:coverage` WARN: the query key `process heat food processing / solar` is `NoReported`
  in `final_energy_map_v9.1` (about 0.04 EJ).
- C: nine SKIP rows from `check_known_violations`.
- D WARN: `lost_row` for the template rows whose mapped base variable the Korea csv does not have
  (the same rows that keep step3 coverage near 50 %).

### Test runs (kaist/scenario)

`kaist/scenario/` keeps two scenario sets as a regression test of the whole pipeline: `input/` holds
the BaseX databases (and the scenario XMLs for u0909), `output/<run>/` the results, and
[scenario/RESULT.md](scenario/RESULT.md) the run record with the per-step findings and a
symptom-to-fix table. Settings: `kmip/config/u0909.R` and `kmip/config/ssp2.R` (local paths, no
reference run, no MT workbook). Last run 2026-10-27 on Windows 11 with R 4.6.1, Java 1.8, one step1
worker per scenario; both runs exited 0:

| Run | Scenarios | Step1 | Step2 | Step3 | Step4 | Step5 | Time |
|---|---|---|---|---|---|---|---|
| reports_u0909 | KAIST_9_ref_u0909, KAIST_9_NZ_u0909 (gcam-kaist9, GHG_Kor cap) | OK, 2 DBs, 105,169 report rows, vetting Inf/NA OK | OK; b9 skipped (no `CO2_LULUCF_adj`) | OK; coverage ref 271/584 (46 %), NZ 294/584 (50 %); submission 1,168 rows | A FAIL (1 of 9: `co2_total` 2035, 2 regions, max 2.2 %), WARN 1 (NoReported key); B PASS 34/34; C PASS 42/42 + 9 known SKIP; D WARN (3,390 ok, 3,372 expected_missing, 246 lost_row, 0 mismatch) | OK, figure only | 42 min, step1 37 min |
| reports_ssp2 | SSP2-Ref, SSP2-NDC-fast, SSP2-NDC-slow (gcam-kaist9) | OK, 3 DBs, 158,817 report rows, vetting Inf/NA OK | OK; b9 skipped | OK; coverage Ref 46 %, NDC 50 %; submission 1,752 rows | A FAIL (1 of 9: `co2_total` 2035, 1 region, max 1.3 %), WARN 1; B PASS 34/34; C PASS 42/42 + 9 known SKIP; D WARN (5,154 ok, 5,058 expected_missing, 300 lost_row, 0 mismatch) | OK, figure only | 45 min, step1 38 min |

What the test run established: the pipeline runs end to end on Windows once `Rscript` is on PATH
and `openxlsx` and `tidyverse` are installed (earlier local attempts died in step3 on those two
packages); the step2 modules a1-a6, b1-b8 all ran (b9 correctly skipped); step4 shows only the
documented non-PASS results above. To repeat: `kaist/kmip/run_pipeline.sh kaist/kmip/config/u0909.R`
(or `ssp2.R`) from the repo root; `--from 2` reuses the step1 outputs.

### kmip/steel: the KMIP2026 steel sheet

KMIP2026 sent its steel sheet before the rest of the template. `kmip/steel/build_steel_template.py` fills that sheet (production, energy and emissions by steel route, capture) from ModelInterface query dumps, outside the R pipeline; `plot_steel_compare.py` draws the comparison charts. The two steel methods it introduced, the coal fuel/feedstock split and the process-emission split, were later moved into step2 (`b3_steel_coal_split.R`, `b6_steel_process_split.R`), so the main template and the steel sheet agree. Step3 still fills only the main template, so the steel sheet comes only from this folder. Delete the folder once the full KMIP2026 template arrives and `make_mapping.R` and step3 cover the steel rows. Method notes: `kmip/steel/README.md`.

## Design notes

1. KAIST code is separate from the package. On `main`, `R/`, `inst/` and `data/` are never edited by hand; they come from the branch `kaist/v9.1-korea`. KAIST customizations live only in `kaist/` (see "Syncing with upstream" below).

2. Run settings per project (`KAIST_CONFIG`). Each run has one config file (run name, database, region, years, scenarios) in its project folder, e.g. `kaist/kmip/config/kaist9_low26.R`. Projects never edit each other's settings. `kaist/core/config.R` is only a loader: every step sources it, it reads the file named by the `KAIST_CONFIG` environment variable and stops with a list of available files if it is not set.

3. One output folder per database. Outputs are written under `kmip/{db_name}_output/`, so different databases do not mix. A config file may set `output_dir` itself (the kaist9 settings keep their first output folder).

4. step2 is a thin orchestrator over `kaist/kmip/modules/`. Each adjustment is one function in one file (`a1` to `a6` run on all regions, `b1` to `b9` on Korea only). All functions are data in, data out, so step2 reads as a list of calls and you can inspect `data` between them. Module files only define functions; sourcing them executes nothing. Order matters in a few places: capacity-changing modules (a2, a3, a4) must run before a5 (parent-child consistency); inside a3 the nuclear addition must come before the renewable multiplier; Part B modules need the Korea-filtered data; b6 (steel process emissions) needs b3's Coal|Feedstock rows; b7 (hybrid Energy Service rows) must run before b4 (vehicle conversion). Otherwise the b* order is arbitrary. `modules/` also holds the shared helpers (`00_utils.R`, `unit_table.R`) and the step4 checks (`validate/`). Values that are not queried from GCAM (Korea statistics, literature ratios, MT vehicle counts) are catalogued in `hardcoded_assumptions.md`, a local note outside the repo (`~/reporting/docs/` on the lab server); update it when you change one of those values. To verify that a refactor changed nothing: `source("kaist/core/tools/compare_outputs.R")` then `compare_csv(old_csv, new_csv)` (md5-based, prints the first differences).

## Quick start

1. Open R in the repo root and run `devtools::load_all(".")` once to
   build the gcamreport package locally.
2. Pick or create a config file in your project folder (copy `kaist/kmip/config/kaist9_low26.R`; set `run_name`, `db_path`, `db_name`, `scenarios`, years, `ignore_markets` and the `compare_*` block) and point `KAIST_CONFIG` to it: `KAIST_CONFIG=kaist/kmip/config/kaist9_low26.R Rscript kaist/kmip/step3_template.R`, or `Sys.setenv(KAIST_CONFIG = "...")` in RStudio. One GCAM database per scenario (gcam-kaist9): merge them into one database first, see below.
   Policy markets (ceilings, floors, caps such as `CO2_Kor`) must be dropped from the price rows, or gcamreport reports their shadow prices as fuel prices. The core list `kaist_ignore_markets` (`kaist/core/functions.R`) covers the KAIST ones and is used unless the config file sets `ignore_markets`; a run with other cap markets writes `ignore_markets <- c(kaist_ignore_markets, "...")`. The same three layers as for the data rows apply: the core list holds the market names of the model, a project adds its own markets in its `functions.R` (for example `ktraces_ignore_markets`), and a config file adds the ones of a single run. Names in the list that a database does not have are harmless. Step1 warns about policy-like market names the list does not cover.
3. If BaseX 9.5+ is installed, source `kaist/core/rgcam_patch.R` once per
   session before step 1 (see the comment block in step1).
4. Run everything with `kaist/kmip/run_pipeline.sh kaist/kmip/config/<run>.R`: step1 with one worker per scenario, then steps 2 to 5 (logs in `{output_dir}/logs/<date>/`; `--from 2` skips step1; `run_steps <- c(1, 2, 4, 5)` in the settings leaves steps out, e.g. no KMIP template for NMSF2). Or run the steps by hand in that order from the repo root. Step5 needs quarto on PATH or in `QUARTO_BIN`.
   `core/` is enough for general use (step1 only); `kmip/` is the KMIP pipeline;
   `ktraces/` builds the K-TRACES workbook from a step1 run made with its config file.

### Parallel step1 (many scenarios)

Each BaseX query uses one CPU, so with several scenarios run one worker per
scenario instead of `step1_generate_report.R`:

```
Rscript kaist/core/tools/step1_parallel.R            # all scenarios in the KAIST_CONFIG config file
Rscript kaist/core/tools/step1_parallel.R --jobs=4   # at most 4 at a time
```

It patches the data once, starts `kaist/core/tools/step1_worker.R <scenario>`
per scenario (logs in `{output_dir}/logs/`), waits, then runs
`kaist/core/tools/step1_merge.R` to build the single `{run_name}.xlsx` and
`{run_name}_project_merged.dat` that step2 expects.

### One database per scenario (gcam-kaist9): merge first

gcam-kaist9 writes one BaseX database per run (e.g. `kmip/KAIST9_LOW26/low_nz/`). Merge the scenarios you want into one database; the config file then points at that database like any other (`db_path`, `db_name`, `scenarios`):

```
Rscript kaist/core/tools/merge_basex_dbs.R list kmip/KAIST9_LOW26        # scenarios in every database of the folder
Rscript kaist/core/tools/merge_basex_dbs.R merge kmip/KMIP26_LOW kmip/KAIST9_LOW26/low_ref kmip/KAIST9_LOW26/low_nz
```

`merge` copies the scenario documents with the BaseX jar (no ModelInterface, no export file); `--pick 1,3` takes rows of the numbered table, `--interactive` asks on the terminal, and `<db folder>:<scenario name>` picks one scenario of a database. A scenario name may be chosen only once. The report keeps the GCAM scenario names; `scenario_labels <- c("KAIST_9_NZ_u1007low" = "low_nz", ...)` in the config file renames them in the merged step1 outputs (then `scenarios` lists the GCAM names and everything after step1 uses the labels).

### Step 5: report

The GHG pathway figure comes from the step2 Korea csv: `Emissions|Kyoto Gases` (net) and net minus LULUCF (gross), one line per scenario; `plot_measures`, `plot_start_year`, `plot_subtitle`, `pathway_targets` and `pathway_caps` in the settings shape it.

The comparison report needs `compare_a_file` in the settings: the KMIP2025 submission workbook (sheet `data`, `compare_a_model`) or a step3 csv of an earlier run. `compare_pair` picks the scenario pair for the variable-by-variable part, `compare_a_scenarios` / `compare_b_scenarios` the lines of the overview, and `compare_ref_step2_csv` (optional) a step2 Korea csv of the reference database for the national gross/net GHG panel. Output: `{output_dir}/compare/{run_name}_compare.pdf` plus one png and csv per section. Without `compare_a_file` step5 makes only the figure.

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

All KAIST customizations live in `kaist/`. Helper functions are in `kaist/core/functions.R`. The data customizations that gcamreport needs for KAIST's GCAM runs (extra mapping rows and capacity-factor overrides for `bio-ceiling`, `irnstl-ceiling`, `Gen_III_Korea`, Korea capacity factors and so on) are applied at runtime by `patch_gcam_data()` in the same file. Step1 and step2 call it right after `devtools::load_all`; it changes the loaded data objects in memory only and never writes the tracked `data/*.rda` files. Step2 and step4 helpers get the patched objects through `load_gcam_rda()`. Rows that only one project needs go into that project's `functions.R` (`kaist/kmip/functions.R`, `kaist/ktraces/functions.R`), which defines `patch_project_data()`; step1 calls it when the config file sources that project file.

## Moving to a new GCAM version

The applier (`patch_gcam_data`) stays the same; only the per-version values change. To support a new version:

1. Set `version_number` in your config file (e.g. `"9.1"`).
2. Open `kaist/core/functions.R` and find the `kaist_overrides` list, one entry per GCAM version (`"v7.0"`, `"v8.2"`, `"v9.1"`). Add a sibling entry keyed by the new GCAM_version string:

   ```r
   kaist_overrides <- list(
     "v9.1" = list( ... ),    # existing, leave as is
     "v9.2" = list( ... )     # add this; copy the closest block and adjust
   )
   ```

   Adjust the values (technology names, CF values, dropped `template` variables) for the new version. If a step errors on a missing or renamed column, check that version's mapping CSV column names in `inst/extdata/mappings/`.
3. Nothing else changes: `patch_gcam_data("v9.2")` picks up the new block through the `paste0("v", version_number)` call in step1 and step2.

## References

- [core/rgcam_patch.R](core/rgcam_patch.R): fix for BaseX 9.5+ compatibility
