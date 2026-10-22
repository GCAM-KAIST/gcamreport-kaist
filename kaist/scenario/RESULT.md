# kaist/scenario - scenario runs

One row per run. Inputs are under `input/`, outputs under `output/<run>/` (one folder per
`output_dir` in the settings file). Run a step from the repo root with the settings file in
`KAIST_CONFIG`, e.g. `KAIST_CONFIG=kaist/kmip/config/ssp2.R Rscript kaist/kmip/step2_process_data.R`.

## Runs

| Run | Settings | Scenarios (BaseX DB) | Last run | Key outputs |
|---|---|---|---|---|
| reports_u0909 | `kaist/kmip/config/u0909.R` | KAIST_9_ref_u0909 ([u0909r](input/u0909/u0909r/)), KAIST_9_NZ_u0909 ([u0909n](input/u0909/u0909n/)); config XML in [input/u0909/](input/u0909/) | 2026-10-19 | [reports_u0909.xlsx](output/reports_u0909/reports_u0909.xlsx), [reports_u0909_korea.csv](output/reports_u0909/reports_u0909_korea.csv), [KMIP2025_DB_final.xlsx](output/reports_u0909/KMIP2025_DB_final.xlsx), [step5_summary.csv](output/reports_u0909/step5_summary.csv), [reports_u0909_ghg_pathway.png](output/reports_u0909/reports_u0909_ghg_pathway.png); logs ([2026-10-04 test run only](output/reports_u0909/logs/)) |
| reports_ssp2 | `kaist/kmip/config/ssp2.R` | SSP2-Ref ([ssp2_ref](input/ssp2/ssp2_ref/)), SSP2-NDC-fast ([ssp2_ndc_fast](input/ssp2/ssp2_ndc_fast/)), SSP2-NDC-slow ([ssp2_ndc_slow](input/ssp2/ssp2_ndc_slow/)); config XML not stored | 2026-10-22 | [reports_ssp2.xlsx](output/reports_ssp2/reports_ssp2.xlsx), [reports_ssp2.csv](output/reports_ssp2/reports_ssp2.csv), [reports_ssp2_project_merged.dat](output/reports_ssp2/reports_ssp2_project_merged.dat); log [step1_ssp2_20261022.log](output/reports_ssp2/logs/step1_ssp2_20261022.log) |

## Step results

Step1 = query BaseX DBs, Step2 = process data, Step3 = create mapping, Step4 = fill template,
Step5 = validate (checkpoints A-D), Step6 = plots. `-` = not run.

| Run | Step1 | Step2 | Step3 | Step4 | Step5 | Step6 |
|---|---|---|---|---|---|---|
| reports_u0909 | OK (2 DBs) | OK | OK | OK; submission xlsx not written (Python step skipped) | A FAIL (4/9 raw-vs-report checks), B PASS, C PASS, D WARN (264 rows lost) | OK ([ghg_pathway.png](output/reports_u0909/reports_u0909_ghg_pathway.png)) |
| reports_ssp2 | OK (3 DBs, 37 min, 158,817 rows, Inf/NA vetting OK) | - | - | - | - | - |

All runs: GCAM 9.1, target region South Korea, years 2005-2050, all regions and variables queried
in step1, market pattern `^bio-ceiling$` ignored. "Last run" is the newest output file date in
`output/<run>/`. Status as of 2026-10-23.
