# kaist/scenario - scenario runs

Folder layout (as of 2026-10-22):

```
scenario/
  input/                     GCAM inputs: BaseX databases (+ the GCAM config XML where available)
    u0909/                   KAIST_9_Ref_u0909.xml, KAIST_9_NZ_u0909.xml, u0909r/, u0909n/
    ssp2/                    ssp2_ref/, ssp2_ndc_fast/, ssp2_ndc_slow/
  output/                    pipeline outputs, one folder per run_name (= output_dir in the settings file)
    reports_u0909/           settings: kaist/kmip/config/u0909.R   (logs in logs/, Oct 1 leftovers in archive_20261001/)
    reports_ssp2/            settings: kaist/kmip/config/ssp2.R    (logs in logs/)
  RESULT.md                  this file
```

Run a step from the repo root with the settings file in `KAIST_CONFIG`, e.g.

```
KAIST_CONFIG=kaist/kmip/config/ssp2.R Rscript kaist/kmip/step2_process_data.R
```

## 1. Input scenarios

| Run | Scenario name (in DB) | BaseX database | GCAM config XML | GCAM version | DB written |
|---|---|---|---|---|---|
| reports_u0909 | KAIST_9_ref_u0909 | [input/u0909/u0909r](input/u0909/u0909r/) | [KAIST_9_Ref_u0909.xml](input/u0909/KAIST_9_Ref_u0909.xml) | 9.1 | 2026-09-30 |
| reports_u0909 | KAIST_9_NZ_u0909 | [input/u0909/u0909n](input/u0909/u0909n/) | [KAIST_9_NZ_u0909.xml](input/u0909/KAIST_9_NZ_u0909.xml) | 9.1 | 2026-09-30 |
| reports_ssp2 | SSP2-Ref | [input/ssp2/ssp2_ref](input/ssp2/ssp2_ref/) | not stored here | 9.1 | 2026-10-01 |
| reports_ssp2 | SSP2-NDC-fast | [input/ssp2/ssp2_ndc_fast](input/ssp2/ssp2_ndc_fast/) | not stored here | 9.1 | 2026-10-02 |
| reports_ssp2 | SSP2-NDC-slow | [input/ssp2/ssp2_ndc_slow](input/ssp2/ssp2_ndc_slow/) | not stored here | 9.1 | 2026-10-06 |

Common settings for both runs: target region South Korea, years 2005-2050, all regions and all
variables queried in step1, market pattern `^bio-ceiling$` ignored.

## 2. Pipeline status (step1 - step5)

| Run | Step1 report | Step2 process | Step3 mapping | Step4 fill template | Step5 validate |
|---|---|---|---|---|---|
| reports_u0909 | OK (2026-10-04) | OK (2026-10-19) | OK (2026-10-19) | OK, submission xlsx not written (2026-10-19) | A FAIL, B PASS, C PASS, D WARN (2026-10-19) |
| reports_ssp2 | OK (2026-10-22) | not run | not run | not run | not run |

Notes

- Status is read from the files in `output/<run>/` and the logs in `output/<run>/logs/`.
  The u0909 step2-6 outputs dated 2026-10-19 come from a later run than the logs in
  `logs/` (2026-10-04, where step3/4/6 failed on missing packages); no log of the
  2026-10-19 run was kept.
- reports_u0909 step4: `variables_before/after_unit_conversion.csv` were written, but
  `reports_u0909_KMIP_submission.xlsx` is missing, i.e. the Python submission-workbook
  step (`write_submission.py`, needs pandas + openpyxl) did not run.
- reports_u0909 step5 (`step5_summary.csv`): A raw-vs-report 5 pass / 4 fail
  (Final Energy non-transport sum and coverage, CO2 total after 2035, CO2 tech coverage);
  B step1-vs-step2 all pass; C tree sums all pass with 9 known-violation skips;
  D template fill 1 warn (264 rows lost).
- Step6 (GHG pathway figure): reports_u0909 produced 2026-10-19; reports_ssp2 not run.
- reports_ssp2 step1 (2026-10-22, 37 min for 3 databases): exit 0, vetting "Inf variables: OK",
  "NA variables: OK" for all three jobs; merged report 158,817 rows, 3 scenarios.

## 3. Output files

### reports_u0909 (`output/reports_u0909/`)

| Step | File |
|---|---|
| 1 | [reports_u0909.xlsx](output/reports_u0909/reports_u0909.xlsx), [reports_u0909_project_merged.dat](output/reports_u0909/reports_u0909_project_merged.dat) (merged); per scenario [reports_u0909_Ref_u0909.xlsx](output/reports_u0909/reports_u0909_Ref_u0909.xlsx), [reports_u0909_NZ_u0909.xlsx](output/reports_u0909/reports_u0909_NZ_u0909.xlsx) (+ .csv, .RData, `_project_*.dat`) |
| 2 | [reports_u0909.csv](output/reports_u0909/reports_u0909.csv) (all regions), [reports_u0909_korea.csv](output/reports_u0909/reports_u0909_korea.csv), [gcam_available_variables.csv](output/reports_u0909/gcam_available_variables.csv) |
| 3 | [kmip_gcam_mapping_template.xlsx](output/reports_u0909/kmip_gcam_mapping_template.xlsx) |
| 4 | [variables_before_unit_conversion.csv](output/reports_u0909/variables_before_unit_conversion.csv), [variables_after_unit_conversion.csv](output/reports_u0909/variables_after_unit_conversion.csv), [KMIP2025_DB_final.xlsx](output/reports_u0909/KMIP2025_DB_final.xlsx) |
| 5 | [step5_summary.csv](output/reports_u0909/step5_summary.csv), [step5_mismatches.csv](output/reports_u0909/step5_mismatches.csv), [step5_unmapped.csv](output/reports_u0909/step5_unmapped.csv) |
| 6 | [reports_u0909_ghg_pathway.png](output/reports_u0909/reports_u0909_ghg_pathway.png), [reports_u0909_ghg_pathway.csv](output/reports_u0909/reports_u0909_ghg_pathway.csv) |
| logs | [logs/](output/reports_u0909/logs/) (2026-10-04 test run, step1-6) |
| old | [archive_20261001/](output/reports_u0909/archive_20261001/): first step1 run of 2026-10-01 (`Ref_u0909.*`, `NZ_u0909.*`, `u0909r_Ref_u0909.dat`, `u0909n_NZ_u0909.dat`), not used by step2 |

### reports_ssp2 (`output/reports_ssp2/`)

| Step | File |
|---|---|
| 1 | [reports_ssp2.xlsx](output/reports_ssp2/reports_ssp2.xlsx), [reports_ssp2.csv](output/reports_ssp2/reports_ssp2.csv), [reports_ssp2_project_merged.dat](output/reports_ssp2/reports_ssp2_project_merged.dat) (merged); per scenario [reports_ssp2_Ref.xlsx](output/reports_ssp2/reports_ssp2_Ref.xlsx), [reports_ssp2_NDC_fast.xlsx](output/reports_ssp2/reports_ssp2_NDC_fast.xlsx), [reports_ssp2_NDC_slow.xlsx](output/reports_ssp2/reports_ssp2_NDC_slow.xlsx) (+ .csv, .RData, `_project_20261022_225956.dat`) |
| 2-6 | not run yet |
| logs | [logs/step1_ssp2_20261022.log](output/reports_ssp2/logs/step1_ssp2_20261022.log) |
