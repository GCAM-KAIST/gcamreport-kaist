# TODO

Open items for the KAIST pipeline. Updated 2026-09-02.

## Waiting on the professor (steel, memo section 7)

- [ ] Process-emission split option for the BF CO2 rows: keep the current
      method (Coal|Feedstock x 0.00193 Mt CO2/ktoe), or switch to option A
      (coal feedstock ratio 0.5832) or option B (MT emission ratio 0.2851).
      Both are computed in `steel_intermediates_*.xlsx` but not filled.
- [ ] Production|Iron / Iron Ore: keep NR (as MT did), or fill Iron from the
      GCAM ore-reduction routes (BF family + DRI routes, scrap EAF excluded).
- [ ] CCS row sign convention and net-vs-gross basis of the CO2 energy row.
- [ ] b6 changes only the steel leaf row. Decide whether the parent CO2 rows
      (`Emissions|CO2|Energy|Demand|Industry`, `...|Demand`,
      `Emissions|CO2|Energy`) should drop by the same amount and
      `Emissions|CO2|Industrial Processes` rise by it.
- [ ] Main template mapping: `Emissions|GHGs|Non-Energy|Industrial Process`
      (parent) is mapped to Cement only. Add the new
      `...|Industrial Process|Iron and Steel` row to it or not.

## Steel tools (kaist/steel/)

- [ ] KMIP2026 full template: when it arrives, rerun step3, review the
      mapping, and stop producing the steel sheet separately (MERGE_PLAN M4).
- [ ] kaist9 NZ run: re-extract `refined liquids production by subsector`
      (GCAM 9 variant) and `CO2 emissions by tech (no bio)` for the NZ
      scenario; the current `query_results_kaist9.xlsx` lacks both.
- [ ] Delete the old copies of `build_steel_template.py` and
      `plot_steel_compare.py` in `kmip/.../iron_report/` once the repo
      versions are in use everywhere.

## Pipeline

- [ ] step4 keeps the source unit label when the conversion factor is 1, so
      `Mt CO2/yr` rows mapped to `Mt CO2eq/yr` template rows keep the
      `Mt CO2/yr` label (values are right). Relabel to the template unit.
- [ ] step5 A `fe_nontrn:coverage` WARN: 2 NoReported keys (KAIST
      `irnstl-ceiling` inputs). Decide if they should be mapped or silenced.
- [ ] step5 D `lost_row` WARN (350): mapping rows whose base variable is
      missing for some scenarios. Review the mapping or add the variables.
- [ ] gcamreport region-scope issue #79 (capacity) is still open upstream.

## kaist9 (GCAM 9.1) migration

- [ ] Add a `"v8.2"` entry to `kaist_overrides` in `kaist/functions.R` and run
      the pipeline against a GCAM 9.1 database (Ukraine region, base year
      2021, SMR techs). Guide: `kaist/docs/task_kaist9_reporting_pipeline.md`.
- [ ] Check `a4_capacity_recalc.R` `tech_to_cap` for new GCAM 9 technologies.
