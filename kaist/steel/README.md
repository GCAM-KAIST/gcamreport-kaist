# Iron and steel reporting (KMIP2026 steel template)

Standalone tools that fill the KMIP2026 **steel-sector** template from GCAM
ModelInterface query dumps. They were built before the full KMIP2026
template set arrived, so they run outside the R pipeline. The methods they
use are also applied inside the main pipeline by the step2 modules
`b3_steel_coal_split.R` (coal Fuel/Feedstock) and
`b6_steel_process_split.R` (process emissions), so both routes give the
same steel numbers.

Data (query dumps, templates, reference workbooks, outputs) stays in the
per-DB output folder `{output_dir}/iron_report/` (gitignored). The Korean
method memo `steel_report_memo.md` lives there too; this README is the
short English version.

## Files

| File | Purpose |
|------|---------|
| `build_steel_template.py` | Fill the steel template from `query_results_{tag}.xlsx`; writes `KMIP2026_steel_GC_{tag}.xlsx` and `steel_intermediates_{tag}.xlsx` |
| `plot_steel_compare.py` | 5 comparison charts from `KMIP2026_steel_compare.xlsx` (+ intermediates) into `charts/` or `charts/en/` |

Python 3 with `pandas`, `openpyxl`, `matplotlib`.

## How to run

From the repo root, `--dir` points at the data folder:

```
python -X utf8 kaist/steel/build_steel_template.py \
    --dir kmip/KMIP25_6Scenarios_output/iron_report                # S1 (tag S1)
python -X utf8 kaist/steel/build_steel_template.py \
    --dir kmip/KMIP25_6Scenarios_output/iron_report \
    --tag ref_con --input query_results_ref.xlsx                   # ref scenario
python -X utf8 kaist/steel/build_steel_template.py \
    --dir kmip/KMIP25_6Scenarios_output/iron_report \
    --tag kaist9_nz --input query_results_kaist9.xlsx \
    --xml kaist/input/Korea/iron_steel_no_h2.xml --base-year 2021  # GCAM 9.1 run
python -X utf8 kaist/steel/plot_steel_compare.py \
    --dir kmip/KMIP25_6Scenarios_output/iron_report [--en]
```

- `--input` defaults to `query_results_{tag}.xlsx` (then `query_results.xlsx`).
- `--xml` is the `iron_steel.xml` of the GCAM run (coal coefficients by
  technology). Default: `gcam_input/gcamdata/xml/iron_steel.xml` in the repo.
  On the lab server the GCAM 7.0 core file is
  `/data/shared/gcam-7.0/xml/iron_steel.xml`.
- Running inside the data folder without `--dir` also works (old behaviour).
- If `KMIP2026_steel_GC_{tag}.xlsx` already exists, its note column (M) is
  kept and only the values are rewritten.
- Log tags to check: `[UNITS OK]`, `[COAL CHECK]`, `[EXCLUDE]`,
  `[FILL]/[NR]/[HOLD]`.

## Required queries in `query_results_{tag}.xlsx`

One sheet per ModelInterface query (row 1 = query title or header):

| Sheet (first 31 chars) | Query |
|---|---|
| `iron and steel inputs by tech (` | iron and steel inputs by tech |
| `iron and steel production by re` | iron and steel production by region |
| `iron and steel production by te` | iron and steel production by tech |
| `CO2 emissions by tech (excludin` | CO2 emissions by tech (excluding resource production) |
| `CO2 emissions by tech (no bio) ` | CO2 emissions by tech (no bio) -- optional, preferred CO2 basis |
| `CO2 sequestration by tech` | CO2 sequestration by tech |
| `nonCO2 emissions by sector (exc` | nonCO2 emissions by sector (excluding resource production) |
| `refined liquids production by s` | refined liquids production by subsector -- **added query**, see below |

### Added query: `refined liquids production by subsector`

Not in the stock `Main_queries.xml`. It gives the national refining mix that
the biomass-liquids split needs. Add it under
*energy transformation > refining* in ModelInterface (both variants are in
`gcam_input/output/queries/Main_queries.xml` of this repo).

GCAM 7 (one `refining` sector):

```xml
<supplyDemandQuery title="refined liquids production by subsector">
  <axis1 name="subsector">subsector</axis1>
  <axis2 name="Year">physical-output[@vintage]</axis2>
  <xPath buildList="true" dataName="output" group="false" sumAll="false">*[@type='sector' and (@name='refining')]/*[@type='subsector']//
    output-primary[@type='output']/physical-output/node()</xPath>
  <comments/>
</supplyDemandQuery>
```

GCAM 9 (separate `oil refining` / `biomass liquids` / `gas to liquids` /
`coal to liquids` sectors; taken from the *GCAM USA > energy transformation >
refining* group):

```xml
<supplyDemandQuery title="refined liquids production by subsector">
  <axis1 name="subsector">subsector</axis1>
  <axis2 name="Year">physical-output[@vintage]</axis2>
  <xPath buildList="true" dataName="output" group="false" sumAll="false">*[@type='sector' and
    (@name='oil refining' or @name='biomass liquids' or @name='gas to liquids' or @name='coal to liquids')]/
    *[@type='subsector']//
    output-primary[@type='output' (:collapse:)]/physical-output/node()</xPath>
  <comments/>
</supplyDemandQuery>
```

## Method summary (memo sections in brackets)

Units: EJ -> ktoe x 23,884.6; MTC -> Mt CO2 x 44/12; units are checked
against each sheet's `Units` column. Inputs `scrap`, `irnstl-ceiling`,
`irnstl_ceiling_EAF` are not energy and are excluded from Final Energy.

1. **Final Energy by fuel** (§1): sector inputs `delivered coal` -> Coal,
   `wholesale gas` -> Gas, `refined liquids industrial` -> Oil,
   `elect_td_ind` -> Electricity, `H2 industrial` -> Hydrogen,
   `delivered biomass` -> Biomass.
2. **Biomass Solids / Liquids** (§2): all liquids come from one national
   refining pool, so `bio_share(y)` = biomass liquids / total refining
   output. `Biomass|Liquids` = Oil x bio_share and is **removed from Oil**;
   `Biomass|Solids` = delivered biomass; `Biomass` = Solids + Liquids.
   Same logic as pipeline module b5.
3. **Coal Fuel / Feedstock** (§3, professor-approved 2026-08-24):
   - Coal is used by the BF family (BLASTFUR, BLASTFUR CCS, BLASTFUR with
     hydrogen) and, in tiny amounts for heating, by EAF with DRI (CCS).
     EAF-DRI coal (~0.1-0.2% of sector coal) is all Fuel.
   - Feedstock share of BF-family coal = MT 2020 Coal|Feedstock / Coal total
     = 15,400.85 / 26,409.01 = **0.5832**, read at runtime from the KMIP2025
     reference workbook (`(붙임 2-1) ...xlsx`, sheet `data`, MT / S1).
   - `Coal|Feedstock` = sector coal x BF-family share(y) x 0.5832; rest =
     `Coal|Fuel`. The script rebuilds coal by technology from production x
     XML coefficient (checked against queried coal within 1%); the pipeline
     module b3 reads coal by technology directly from the
     `industry final energy by tech and fuel` query.
   - Other fuels: Biomass / Oil / Gas all Fuel, Hydrogen all Feedstock.
4. **CO2 basis and process emissions** (§4, confirmed 2026-08-24):
   - Energy CO2 basis = the **no-bio** query (biogenic CO2 neutral, IAMC
     convention; gcamreport does the same, so the main pipeline's
     `Emissions|CO2|Energy|Demand|Industry|Iron and Steel` equals it).
   - Process CO2 = `Coal|Feedstock` (ktoe) x **0.00193 Mt CO2/ktoe**, the MT
     2020 ratio process CO2 / Coal|Feedstock = 29.648 / 15,400.8 (runtime).
   - Energy row = no-bio total - process, so energy + process = no-bio total.
   - Pipeline module b6 does the same to the korea csv.
5. **CH4 / N2O** (§5): AR6 GWP100, CH4 x 27.2, N2O x 273 (same as step4).
6. **Production** (§6): Steel from `iron and steel production by region`;
   Iron and Iron Ore are NR (GCAM has no separate output; MT also reported
   0 last year).

## Open decisions (memo §7, waiting on the professor)

Not implemented until decided:

- Process-emission split of the BF CO2 rows: option A (coal feedstock ratio
  0.5832) vs option B (MT emission ratio 0.2851). The submission uses the
  §4 method above; A/B are computed in `steel_intermediates_*.xlsx`
  (`process_split_proposal`) but not filled (`--no-process-split` leaves the
  process row blank).
- Production|Iron / Iron Ore: keep NR, or derive Iron from the ore-reduction
  routes (BF family + DRI routes, scrap EAF excluded).
- CCS row sign and net-vs-gross CO2 for the energy row.
- Main KMIP template: b6 changes only the steel leaf row. Whether the parent
  CO2 rows (`...|Industry`, `...|Demand`, `Emissions|CO2|Energy`) and
  `Emissions|CO2|Industrial Processes` should move by the same amount is
  not decided.

## GCAM 9.1 (kaist9) notes (§9)

- Base year 2021: the 2020 column is left blank (`--base-year 2021`).
- The Korea `iron_steel_no_h2.xml` only carries calibrated-tech
  coefficients; CCS techs borrow their sibling's, so the coal reconstruction
  is approximate (reported as a gap, not an error). The split only needs
  "BF coal = sector coal - EAF-DRI coal", so the result is insensitive.
- Re-extract `refined liquids production by subsector` (GCAM 9 variant) and
  `CO2 emissions by tech (no bio)` for the NZ scenario before final use.
