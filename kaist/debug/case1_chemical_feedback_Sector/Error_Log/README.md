# Case 1 — `chemical feedstocks` coal/gas technologies break `get_co2_sequestration()` (GCAM v9.1)

> Copy of the record kept in `gcamreport-temp/debug/case1_chemical_feedback_Sector/Error_Log/`.
> In `gcamreport-kaist/forked` the same fixes are applied at runtime instead of by editing the
> package: fixes 1-7 as `kaist_overrides$v9.1` in `kaist-pj/core/functions.R` (`patch_gcam_data()`),
> fix 8 by `kaist-pj/core/gcamreport_patch.R`. See the table in `kaist-pj/README.md`,
> section "GCAM v9.1: KAIST u0909 scenarios".

Debugging record for the two KAIST GCAM v9.1 scenarios `KAIST_9_ref_u0909` (database `u0909r`)
and `KAIST_9_NZ_u0909` (database `u0909n`) processed with `gcamreport-temp`.

Date: 2026-10-01. Machine: Windows 11, R 4.6.1, GCAM v9.1 Windows release package.

## 0. Scope changes versus the original request

* **GCAM was not re-run.** The configuration files `Input/KAIST_9_NZ_u0909.xml` and
  `Input/KAIST_9_Ref_u0909.xml` reference 52 files under `../input/Korea/`, plus
  `../input/magicc/inputs/input_gases.emk` and `../input/solution/cal_broyden_config_10000.xml`.
  None of these exist in `C:\Users\pjhan\Desktop\GCAM\gcam-v9.1-Windows-Release-Package` and a
  search of the whole user profile found no copy. A time-limited test launch of `gcam.exe` with the
  Ref configuration aborted while parsing scenario components:

  ```
  Parsing ../input/solution/cal_broyden_config_10000.xml scenario component.
  Could not open: ../input/solution/cal_broyden_config_10000.xml failed with: failed opening file: The system cannot find the file specified.
  ```

  The user then asked to skip step 1 and use the databases already present in
  `Input/u0909n` and `Input/u0909r` (BaseX databases dated 2026-09-30, scenario date
  `2026-30-9T22:55:47+09:00`). Everything below uses those databases.

* **`debug.R` was edited for Windows paths.** The original script used Linux paths
  (`/home/jin-lee/gcamreport_temp`, `/home/jin-lee/gcam-v9.1/output`). A copy of the original is
  kept as `Error_Log/debug_original_linux_paths.R`. Only the two path strings changed:

  | Variable | Old | New |
  |---|---|---|
  | `setwd()` | `/home/jin-lee/gcamreport_temp` | `C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp` |
  | `db_path` | `/home/jin-lee/gcam-v9.1/output` | `.../gcamreport-temp/debug/case1_chemical_feedback_Sector/Input` |

  Reports therefore go to `Input/reports_u0909/` and the rgcam project files to
  `Input/u0909r_Ref_u0909.dat` and `Input/u0909n_NZ_u0909.dat`, exactly as the script's logic dictates.

## 1. Error

Reproduced on Windows with the unmodified package (`Error_Log/run1_reproduce.log`), identical to the
earlier Linux failure in `Error_Log/process_u0909_retry.log`:

```
Error in left_join_strict(., get(paste("carbon_seq_tech_map", GCAM_version,  :
  Error: Some rows in the left dataset do not have matching keys in the right dataset.
  Some of the rows that the mapping carbon_seq_tech_map_v9.1 miss are:
  sector              technology
  chemical feedstocks gas
  chemical feedstocks coal
```

Raised in `get_co2_sequestration()` (`R/functions.R`, the `left_join_strict()` onto
`carbon_seq_tech_map_v9.1`), after the project was created and `co2_sequestration_clean` started.

## 2. Diagnosis

* The query `CO2 sequestration by tech` in the saved project (`Input/u0909r_Ref_u0909.dat`) contains
  nine distinct sector/subsector/technology combinations. Three of them belong to
  `chemical feedstocks`: `refined liquids`, `gas` and `coal`.
* The KAIST scenarios add coal and gas feedstock technologies through the custom inputs
  `../input/Korea/chemical_feedstocks_coal.xml` and `../input/Korea/chemical_feedstocks_gas.xml`.
  These technologies report non-zero "sequestration", which in GCAM feedstock sectors is the
  feedstock carbon locked into products (e.g. China coal ≈ 719 MtC cumulative, USA gas ≈ 723 MtC
  cumulative over 1975-2050 in the Ref scenario).
* Core GCAM v9.1 only has the `refined liquids` feedstock technology, so the packaged mapping
  `inst/extdata/mappings/GCAM9.1/carbon_seq_tech_map.csv` (and the derived
  `data/carbon_seq_tech_map_v9.1.rda`) has no row for `chemical feedstocks` + `gas` or `coal`.
  `left_join_strict()` is deliberately strict, so the missing keys abort the report.
* Other mappings already cover these technologies (`CO2_tech_map.csv` rows 37-40,
  `final_energy_map.csv` rows 43-46), so only the carbon sequestration map was incomplete.

## 3. Fix applied in `gcamreport-temp`

1. `inst/extdata/mappings/GCAM9.1/carbon_seq_tech_map.csv`: two rows added directly after the
   existing `chemical feedstocks,refined liquids` rows, copying the same variable hierarchy:

   | sector | technology | var3 (utilization type) | other vars | unit_conv |
   |---|---|---|---|---|
   | chemical feedstocks | gas | `Carbon Capture\|Utilization\|Gases` | `Carbon Capture`, `…\|Utilization`, `…\|Energy`, `…\|Energy\|Fossil`, `…\|Energy\|Demand`, `…\|Energy\|Demand\|Fossil`, `…\|Energy\|Demand\|Industry`, `…\|Energy\|Demand\|Industry\|Fossil`, `…\|Energy\|Demand\|Industry\|Chemicals`, `…\|Energy\|Demand\|Industry\|Chemicals\|Fossil` | 3.666667 |
   | chemical feedstocks | coal | `Carbon Capture\|Utilization\|Other` | same as above | 3.666667 |

   Assumptions:
   * The existing `refined liquids` feedstock row is mapped to `Carbon Capture|Utilization|Liquids`,
     i.e. the utilization sub-category follows the feedstock fuel. Gas therefore maps to
     `…|Utilization|Gases`. The IAMC template has no `Solids` sub-category, so coal maps to
     `…|Utilization|Other`. Both variables exist in
     `inst/extdata/template/GCAM9.1/common-definitions-template.csv`.
   * No `Carbon Removal|Long-Lived Materials|Other` row was added. For refined liquids that row is
     scaled by `refliq_bioshare` (biogenic share of refined liquids). Coal feedstock has no biogenic
     share, and the package computes no equivalent biogenic share for gas, so a removal row would
     either be zero or over-count. If a gas biogenic share is needed later, it must be computed
     like `get_refliq_bioshare()`.
2. `data/carbon_seq_tech_map_v9.1.rda` regenerated with the same code as
   `inst/extdata/saveDataFiles_GCAM9.1.R` (`readr::read_csv(..., comment="#", na="") %>% gather_map()`
   then `usethis::use_data(..., overwrite = TRUE)`). Row count 673 → 695 (11 variables × 2 rows).
   The previous CSV and `.rda` are kept as `Error_Log/carbon_seq_tech_map_v9.1_BEFORE.*`.

No R code was changed.

## 4. Second error (found on Windows after fix 1): energy price map

The Linux retry log stopped at the carbon sequestration error, so nothing after it had ever run.
Run 2 (`Error_Log/run2_fixed_ref_fastload.R/.log`: fixed package, Ref scenario loaded from the
rgcam project saved by run 1 instead of re-querying) passed `co2_sequestration_clean` and then failed
in `get_energy_prices()` (`R/functions.R`, `left_join_strict(energy_price_map, by = "market")`):

```
Some of the rows that the mapping  miss are:
  market
1 cement-ceiling
2 coal-ceiling
3 imported H2
4 rowbio-ceiling
```

### Diagnosis

A scan of every market name in the `prices of all markets` query (after the function strips the
region prefix) against `energy_price_map_v9.1` (`Error_Log` → `scan_markets.R` logic) found exactly
five KAIST-only markets: `bio-ceiling`, `cement-ceiling`, `coal-ceiling` (South Korea constraint
policies from `bio/cement/coal_constraint_*.xml`), `rowbio-ceiling` (rest-of-world bio constraint) and
`imported H2` (South Korea hydrogen import market from `H2_shipping_trade.xml` / `H2_truck_trade.xml`).
`bio-ceiling` only survived because `debug.R` passes `ignore = "^bio-ceiling$"`.

### Fix applied in `gcamreport-temp`

`inst/extdata/mappings/GCAM9.1/en_price_map.csv`: five rows added right after the existing
`globalbio-ceiling,NoReported,...` row (the package's own precedent for a policy-constraint market),
each mapped to `NoReported` with `unit_conv = 1`:
`bio-ceiling`, `rowbio-ceiling`, `cement-ceiling`, `coal-ceiling`, `imported H2`.

Assumption: constraint ("ceiling") markets are policy shadow prices, not energy prices, and the
imported hydrogen market is an intermediate trade market whose price is already represented by
`H2 central production` → `Price|Secondary Energy|Hydrogen`. None of them should appear in the IAMC
price variables. (An alternative that needs no package change is to extend the `ignore` argument in
`debug.R` with these five names.)

`data/energy_price_map_v9.1.rda` regenerated. Originals kept as `Error_Log/en_price_map_v9.1_BEFORE.csv`
and `Error_Log/energy_price_map_v9.1_BEFORE.rda`.

### Side finding: readr type guessing silently drops mapping rows

Regenerating with the exact code in `inst/extdata/saveDataFiles_GCAM9.1.R`
(`readr::read_csv(..., comment = "#", na = "")`) produced *fewer* rows than the shipped `.rda`
(2291 vs 2297). readr/vroom samples rows to guess column types; the sparse columns `var20`–`var29`
were guessed as logical, so the handful of rows that use them (`delivered coal`, `delivered gas`,
lighting/cooking electricity rows, …) parsed as NA and were dropped by `gather_map()`.

The regeneration therefore reads with explicit types:
`col_types = readr::cols(.default = readr::col_character(), unit_conv = readr::col_double())`.
With that, the regenerated map is a strict superset of the shipped one: the 5 intended rows plus **two
rows that the shipped `.rda` had evidently lost to the same bug** when it was built:

| market | var |
|---|---|
| delivered coal | `Price\|Final Energy\|Residential\|Space Heating\|Solids` |
| delivered coal | `Price\|Final Energy\|Residential\|Space Heating\|Solids\|Coal` |

The soft scan (§4c) then showed that restoring these two rows is the *only* remaining strict-join
failure in the Ref scenario: the downstream `en_demand_price_map_v9.1` has no entry for those two price
variables, so the shipped `.rda` was effectively consistent with the rest of the package. **Decision:
keep the shipped behaviour.** The final `data/energy_price_map_v9.1.rda` is built from the CSV with
explicit types and then the two `delivered coal` space-heating rows are removed, and an assertion checks
new = shipped + exactly the 5 new rows (`regen_price_map3.R` logic, recorded in this README). The
CSV/`.rda` discrepancy for `delivered coal` therefore remains as it was before this debugging; fixing it
properly means also extending `en_demand_price_map.csv`, which is out of scope here.

The carbon sequestration map regeneration was checked the same way: new = old + the 22 intended rows,
nothing lost.

Recommendation for the package: add the explicit `col_types` to every `read_csv` in
`inst/extdata/saveDataFiles_GCAM*.R`, otherwise future regenerations depend on readr's sampling.

## 4b. Third error: primary energy map (`coal-ceiling`, `uranium`)

Run 3 (`Error_Log/run3_fixed_ref_fastload.R/.log`, fixes 1+2 applied) passed the energy price step
and 40 variables, then failed in `get_primary_energy()` (`R/functions.R`,
`left_join_strict(primary_energy_map_v9.1, by = "fuel")`):

```
  fuel
1 coal-ceiling
2 uranium
```

### Diagnosis

The `primary energy consumption with CCS by region (direct equivalent)` query in the KAIST project
contains four fuels that core GCAM v9.1 never produces:

| fuel | Units | where | what it is |
|---|---|---|---|
| `bio-ceiling` | EJ | 32 regions | bio constraint policy (passes today only via `ignore`) |
| `cement-ceiling` | "EJ or Mt" | South Korea | cement constraint policy; already dropped by the function's `Units == "EJ"` filter |
| `coal-ceiling` | EJ | South Korea, 2 rows | coal constraint policy |
| `uranium` | EJ | South Korea, 2030-2050 | extra nuclear fuel flow from `nuclear_FT_plan11c.xml`; 0.002-0.005 EJ/yr next to 0.3-0.55 EJ/yr of `e nuclear` |

### Fix applied in `gcamreport-temp`

`inst/extdata/mappings/GCAM9.1/primary_energy_map.csv`:

* `uranium` → `Primary Energy`, `Primary Energy|Nuclear`, `unit_conv = 1` (inserted after `e nuclear`).
  Assumption: the KAIST nuclear technology consumes a separate `uranium` resource instead of the core
  `nuclearFuelGenIII` chain, so its primary energy is *not* already inside `e nuclear`. It is the same
  mapping core uses for `e nuclear`. If it turns out to double count, change the row to `NoReported`;
  the amount involved is about 1-2 % of South Korea's nuclear primary energy.
* `bio-ceiling`, `coal-ceiling`, `cement-ceiling` → `NoReported` (inserted after the existing
  `bio_ceiling` / `bio_ceiling CCS` NoReported rows, which are the core precedent; note core spells it
  with an underscore while the KAIST policies use a hyphen).

`data/primary_energy_map_v9.1.rda` regenerated with explicit `col_types`; verified new = old + 5 rows,
nothing lost. Originals in `Error_Log/primary_energy_map_v9.1_BEFORE.*`.

## 4c. Soft scan to find all remaining gaps in one pass

Finding missing keys one failure at a time costs about ten minutes per iteration, so
`Error_Log/run4_softscan_ref.R` runs `generate_report()` with `left_join_strict()` temporarily replaced
(inside the loaded namespace only, nothing in the package changes) by a version that logs every
unmatched key set and drops those rows instead of stopping. Its log and `run4_softscan_ref.rds` list
every mapping gap for the Ref scenario; the NZ scenario is scanned the same way afterwards.

**Result for Ref (`run4_softscan_ref.log`):** with fixes 1-3 loaded, all 85 internal variables loaded,
the standardized report was written and vetting passed (Inf: OK, NA: OK). The only logged gap was the
self-inflicted `delivered coal` pair discussed in §4, which was then removed from the map again.

## 4d. NZ scenario: soft scan results and fixes 4-5

`Error_Log/run5_softscan_nz.R/.log` (create path: queries the `u0909n` database, saves
`Input/u0909n_NZ_u0909.dat`, then processes with the logging join). All 85 variables loaded, report
written, vetting OK. Two gaps logged:

| mapping | missing keys | cause |
|---|---|---|
| `energy_price_map_v9.1` | `dac-ceiling`, `CO2_Kor`, `rowCO2`, `rowCO2_LUC` | KAIST DAC constraint and CO2 policy markets appearing in `prices of all markets` |
| `primary_energy_map_v9.1` | `bio-ceiling CCS` | CCS variant of the bio constraint "fuel" |

**Fix 4** (`en_price_map.csv`): the four markets → `NoReported`, following the existing rows for
`CO2`, `CO2_LUC`, `globalCO2`, `ROWCO2`, `airCO2` and `process heat dac` (all `NoReported`; carbon
prices are reported through the dedicated CO2 price functions, not the energy price map).
**Fix 5** (`primary_energy_map.csv`): `bio-ceiling CCS` → `NoReported`, following `bio_ceiling CCS`.
Both `.rda` files regenerated with explicit column types; assertions: new = old + 9 rows and
new = old + 6 rows respectively, nothing lost.

### Accuracy finding (not a crash): rest-of-world carbon price was reported as zero

In the NZ soft-scan output `Price|Carbon` was non-zero only for South Korea. The `CO2 prices` query
contains (1990$/tC): `South KoreaCO2` (= `South KoreaCO2_Kor`, 302 in 2030, 3113 in 2050),
`rowCO2` (278 in 2030, 417 in 2050) and the LUC counterparts. `get_co2_price_fragmented_tmp()` maps
markets to regions through `co2_market_v9.1` (`inst/extdata/mappings/GCAM9.1/CO2market_new.csv`),
which knows core's rest-of-world market **`ROWCO2`** (mapped to all 32 regions) but not the KAIST
spelling **`rowCO2`**, so 31 regions silently got a zero carbon price. The function also only
de-duplicates rest-of-world rows against regional markets when the name contains upper-case `ROW`.

**Fix 6** (`CO2market_new.csv`): 31 rows `rowCO2,<region>` for every region in the `ROWCO2` list
*except South Korea*, which already has its own regional market (`South KoreaCO2`). `CO2_Kor` is
deliberately **not** mapped: it carries the same prices as `South KoreaCO2`, and the function sums
market values per region, so mapping it would double Korea's carbon price. `rowCO2_LUC` needs no
mapping because the function drops any market containing `LUC`. `data/co2_market_v9.1.rda`
regenerated (125 → 156 rows, assertion checked). Originals in `Error_Log/CO2market_new_v9.1_BEFORE.csv`
and `Error_Log/co2_market_v9.1_BEFORE.rda`.

Expected effect: `Price|Carbon*` for the 31 non-Korea regions in the NZ report changes from 0 to the
`rowCO2` value converted to 2010US$/tCO2 (about 114 in 2030, 170 in 2050). The Ref scenario has no
CO2 price market ("CO2 prices query is empty!" warning) and is unaffected.

## 5. Why `bio-ceiling` failed on Windows but not on Linux: `debug.R` has `ignore` commented out

Run 1 (and later runs 8, 10, 11) failed in `get_ag_demand()` on `input = bio-ceiling, sector = regional
biomass` although the script appeared to pass `ignore = "^bio-ceiling$"`. The Linux retry log passed
this step. After a long isolation (runs 2-3, 7, 9-18, see §6.1) the instrumented run 18 printed the
call as matched inside `generate_report()`:

```
generate_report(db_path = db_path, db_name = job$db, prj_name = ..., scenarios = job$scenario,
                GCAM_version = GCAM_version, final_year = 2050, desired_regions = "All", ...)
```

There is no `ignore` argument. The current `debug.R` (and the backup `Error_Log/debug_original_linux_paths.R`
taken at 13:00 before the path edit) contain

```r
    # ignore = "^bio-ceiling$",
```

whereas the Linux twin `Input/process_u0909.R` (12:17) has the line active. The line was commented out
in the IDE between the first read of `debug.R` (about 12:50, still active) and 13:00. Every script
derived from `debug.R` by path substitution (runs 1, 8, 10, 11) inherited the comment and ran with
`ignore = NULL`; every script typed by hand for the isolation (runs 2, 3, 7, 9, 12, 13) had the argument
active and passed. The apparent "fails only inside the `for` loop" pattern was an artefact of which
scripts were derived from `debug.R` and which were written by hand. **There is no package bug in the
`ignore` mechanism** (the direct tests in §6.1 confirm it works).

**Fix 7 (keeps `debug.R` working as it is now):** `inst/extdata/mappings/GCAM9.1/ag_demand_map.csv`
gets the row `bio-ceiling,regional biomass,NoReported,…,1` (what the `ignore` pattern was meant to do),
`data/ag_demand_map_v9.1.rda` regenerated and asserted (328 → 329 rows). With it `debug.R` completes
both scenarios without needing `ignore` (run 14, load path; run 16, full create path, §6.2). Whether to
un-comment `ignore` in `debug.R` is the user's choice; it is harmless either way.

Lesson recorded for the log: when a run fails "despite" an argument, print the matched call
(`sys.call()`) first, before chasing environment or data differences.

## 5b. Package bug found by the final run: all carbon prices vanish when `ignore` is not given

Run 16 (`debug.R` as written, no `ignore`, fixes 1-7) completed both scenarios, but comparing its NZ
output with run 6 (same package except fix 7, `ignore` given) showed exactly 66 differing rows:
`Price|Carbon` and `Revenue|Government` for all 33 regions were **0** in run 16 (e.g. South Korea 2050:
1287 → 0; World 2050 revenue: 623 → 0). The Ref output was identical in both runs.

Cause (`R/functions.R`, `get_co2_price_fragmented_tmp()`, two places):

```r
dplyr::filter(!grepl(paste(.myGlobals$ignore.global, collapse = "|"), market))
```

With no `ignore`, `.myGlobals$ignore.global` is `NULL`, `paste(NULL, collapse = "|")` is `""`, and
`grepl("", market)` is `TRUE` for every market, so the filter removes every CO2 price market. The
function then finds `nrow(co2_price_fragmented_pre) <= 1`, sets `co2_price_fragmented <- NULL`, and
every downstream carbon-price variable is zero. This affects **any** `generate_report()` call without
`ignore` on a database that has CO2 prices (the core v9.1 Reference has none, which is why Testrun.R
never showed it). On Linux the step was masked because `process_u0909.R` passes `ignore`.

**Fix 8 (R code, the only code change in this debugging):** new internal helper in `R/functions.R`

```r
is_ignored <- function(x) {
  ig <- .myGlobals$ignore.global
  if (length(ig) == 0) return(rep(FALSE, length(x)))
  grepl(paste(ig, collapse = "|"), x)
}
```

and both filters replaced by `dplyr::filter(!is_ignored(market))`. Behaviour with a non-empty `ignore`
is unchanged. The `for (ign in unique(.myGlobals$ignore.global))` loop in `get_energy_price_tmp()` is
already safe with `NULL`. Original file kept as `Error_Log/functions_BEFORE_fix8.R`.
Verification: run 19 (§6.1/6.2).

## 6. Verification

### 6.1 Run log (all on Windows, R 4.6.1, `gcamreport-temp` loaded with `devtools::load_all`)

| run | script / log (in `Error_Log/`) | package state | project | result |
|---|---|---|---|---|
| 1 | `debug.R` → `run1_reproduce.log` | unmodified | Ref, created from DB | failed in `get_ag_demand()` on `bio-ceiling` (§5) |
| 2 | `run2_fixed_ref_fastload.R/.log` | fix 1 | Ref, loaded | failed in energy price map (§4) |
| 3 | `run3_fixed_ref_fastload.R/.log` | fixes 1-2 | Ref, loaded | failed in primary energy map (§4b) |
| 4 | `run4_softscan_ref.R/.log/.rds` | fixes 1-3, logging join | Ref, loaded | completed; only the self-inflicted `delivered coal` gap |
| 5 | `run5_softscan_nz.R/.log/.rds` | fixes 1-3, logging join | NZ, created from DB | completed; gaps → fixes 4-5 (§4d) |
| 6 | `run6_verify_nz_fastload.R/.log` | fixes 1-6, real join | NZ, loaded | **completed**, 85 variables, vetting Inf/NA OK |
| 7 | `run7_verify_ref_fastload.R/.log` | fixes 1-6, real join | Ref, loaded | **completed**, 85 variables, vetting Inf/NA OK |
| 8 | `debug.R` → `run8_final_debugR.log` | fixes 1-6 | Ref, created from DB | failed in `get_ag_demand()` (`ignore` commented out, §5) |
| 9 | `run9_diag_create_path.R/.log` | fixes 1-6, original join + diagnostics, `ignore` active | Ref, created from DB | completed |
| 10 | `run10_debugR_loadpath.R/.log` | fixes 1-6, `debug.R` verbatim (no `ignore`) | Ref, loaded | failed in `get_ag_demand()` |
| 11 | `run11_debugR_withdplyr.R/.log` | as 10 + `library(dplyr)` | Ref, created from DB | failed in `get_ag_demand()` |
| 12 | `run12_debugR_loadpath_unrolled.R/.log` | fixes 1-6, hand-written call with `ignore` | Ref, loaded | completed |
| 13 | `run13_debugR_loadpath_jobargs.R/.log` | as 12 with `job$...` arguments | Ref, loaded | completed |
| 14 | `run14_debugR_loop_diag.R/.log` | fixes 1-7, `debug.R` structure, diagnostic join | both, loaded | **completed** (fix 7 makes `ignore` unnecessary) |
| 15, 17, 18 | `run15/17/18_*.R/.log` | fix 7 undone in memory, diagnostic join | Ref, loaded | failed as expected; run 18 printed the matched call without `ignore` (§5) |
| 16 | `debug.R` → `run16_final_debugR_prefix8.log` | fixes 1-7 | both, created from DB | completed, but NZ carbon prices all 0 → §5b |
| 19 | `run19_verify_nz_noignore_fix8.R/.log` | fixes 1-8, no `ignore` | NZ, loaded | **completed**; output identical to run 6 (0 differing rows), `Price\|Carbon` restored in 33/33 regions |
| 20 | `debug.R` → `run20_final_debugR_fix8.log` | fixes 1-8 | both, created from DB | **completed**, reports identical to runs 7 / 19 (§6.2) |

Runs 6, 7 and 19 wrote their reports to a scratch folder; runs 8, 16 and 20 are the user's script unchanged
(apart from the Windows paths) and write to `Input/reports_u0909/`.

NZ cross-check (run 6 vs run 5 output, same package except fix 6): identical row set (90 833 rows);
the only differing rows are `Price|Carbon` and `Revenue|Government` (all 32 regions + World) and
the World-level biomass solids price variables, which went from slightly negative (e.g. −0.66) to
positive (≈4.2 2010US$/GJ) once the rest-of-world carbon price stopped being zero. `Price|Carbon`
in 2030 / 2050: South Korea 124.9 / 1287.0, every other region 114.9 / 172.4 (2010US$/tCO2).

### 6.2 Final `debug.R` run (both scenarios, projects re-created from the databases)

Run 20 (`Error_Log/run20_final_debugR_fix8.log`, 22:22-22:51, no network stall): `debug.R` exactly as it
is now (Windows paths, `ignore` commented out), package with fixes 1-8.

| scenario | project | report files (`Input/reports_u0909/`) | variables loaded | vetting |
|---|---|---|---|---|
| `KAIST_9_ref_u0909` (`u0909r`) | created → `Input/u0909r_Ref_u0909.dat` | `Ref_u0909.csv/.xlsx/.RData` | 85 | Inf OK, NA OK |
| `KAIST_9_NZ_u0909` (`u0909n`) | created → `Input/u0909n_NZ_u0909.dat` | `NZ_u0909.csv/.xlsx/.RData` | 85 | Inf OK, NA OK |

Content checks (`helper_scripts/cmp_run20.R`):

| report | rows | variables | regions | compared with | differing rows |
|---|---|---|---|---|---|
| `Ref_u0909.csv` | 88 993 | 2 888 | 33 | run 7 (`Ref_verify.csv`, loaded project, `ignore` given) | 0 |
| `NZ_u0909.csv` | 90 833 | 2 944 | 33 | run 19 (`NZ_noignore_fix8.csv`) and, transitively, run 6 | 0 |

`Price|Carbon` is non-zero in 33/33 regions of the NZ report (South Korea 2030/2050: 124.9 / 1287.0;
other regions 114.9 / 172.4 2010US$/tCO2). South Korea's `Carbon Capture|Utilization|Other` (coal
feedstock, fix 1) and `Primary Energy|Nuclear` (incl. `uranium`, fix 3) are populated.

The earlier full run with fixes 1-7 only (run 16, `run16_final_debugR_prefix8.log`) produced the same
Ref report but an NZ report with all carbon prices equal to zero; those files were overwritten by run 20.

### 6.3 `Testrun.R` (core GCAM v9.1 Reference database) after the changes

`Testrun.R` (as currently written: `gcamreport_run(test_ = TRUE, gcamreport_version_ = "v9.1",
gcam_file_version_ = "v9.1", run_type_ = "report")`, i.e. `generate_report()` with `launch_ui = TRUE`)
was run unattended with `Error_Log/helper_scripts/run_testrun.sh` on the final package state (fixes 1-8).
Log: `Error_Log/testrun_v9.1.log`. Before any change, the previous outputs in
`C:/Users/pjhan/Desktop/GCAM/gcam-v9.1-Windows-Release-Package/output/` (dated 2026-09-24) were copied
aside as the baseline.

* Project re-created from `database_basexdb`, all 85 internal variables loaded, vetting `Inf: OK`,
  `NA: OK`, `gcam_v9.1_report_standardized.{csv,xlsx,RData}` written.
* UI: `Launching UI...` → `Listening on http://127.0.0.1:4566` (Shiny started; the wrapper then stopped
  the R process, since the UI blocks forever).
* Accuracy (`Error_Log/helper_scripts/compare_testrun.R`, baseline vs new CSV):

  | | baseline | new |
  |---|---|---|
  | rows | 88 961 | 88 961 |
  | key rows only on one side | 0 | 0 |
  | rows with any absolute difference > 1e-9 | 0 | |
  | max absolute / relative difference | 0 / 0 | |

  The core Reference output is byte-for-byte unchanged, as expected: every added mapping row keys on a
  name that core GCAM never produces, and fix 8 only matters when CO2 price markets exist.

An earlier Testrun started two minutes before fix 8 was applied was aborted and restarted
(`Error_Log/testrun_v9.1_aborted_prefix8.log`) so that the comparison reflects the final code.

### 6.4 Repository state at the end

Fixes 1-6 plus this `debug/` folder were committed by the user at 21:32 (`72e83cd debug`). Fixes 7
(`ag_demand_map.csv` + `.rda`) and 8 (`R/functions.R`) are uncommitted changes in the working tree of
`gcamreport-temp`; nothing was committed by the debugging session itself. Experiment-only rgcam project
files (`u0909r_Ref_diag.dat`, `u0909r_Ref_u0909_run11.dat`) were moved out of `Input/` to the session
scratch folder; `Input/` holds only the two databases, the two configuration XMLs, `process_u0909.R`,
the two project files written by run 20 and `reports_u0909/`.

## 6b. Operational note: database queries stall while the network is down

Twice during this session the Windows machine lost its internet connection. Each time the running
`generate_report()` stopped making progress in the query phase (rgcam → Java ModelInterface → BaseX)
and resumed the instant the connection returned: run 8 paused 61 min on query 15 (13:54-14:55), run 9
paused 10 min and then 6 h on query 56 (15:21-21:22). No error is raised; the process simply waits.
The timestamps are visible in the `In Function:` / `After Function:` lines of the logs (ms since epoch).
Practical consequence: run the query phase with a stable connection, or create the rgcam project once
and pass its full path as `prj_name` so later runs load it instead of re-querying (runs 2-4, 6, 7 did
this and each finished in about 8 minutes).

## 7. Summary of all changes made to `gcamreport-temp`

Changes 1-7 are mapping data only; change 8 is a small R code fix. Each `.rda` was rebuilt from its CSV with
explicit `col_types` and checked to be the shipped table plus exactly the listed rows.

| # | file(s) | rows added | why |
|---|---|---|---|
| 1 | `inst/extdata/mappings/GCAM9.1/carbon_seq_tech_map.csv`, `data/carbon_seq_tech_map_v9.1.rda` | `chemical feedstocks` × `gas`, `coal` (11 variables each) | KAIST coal/gas feedstock technologies report sequestration |
| 2 | `inst/extdata/mappings/GCAM9.1/en_price_map.csv`, `data/energy_price_map_v9.1.rda` | `bio-ceiling`, `rowbio-ceiling`, `cement-ceiling`, `coal-ceiling`, `imported H2` → NoReported | KAIST constraint / H2 import markets |
| 3 | `inst/extdata/mappings/GCAM9.1/primary_energy_map.csv`, `data/primary_energy_map_v9.1.rda` | `uranium` → Primary Energy(+\|Nuclear); `bio-ceiling`, `coal-ceiling`, `cement-ceiling` → NoReported | KAIST nuclear fuel resource and constraints |
| 4 | `en_price_map.csv` / `energy_price_map_v9.1.rda` | `dac-ceiling`, `CO2_Kor`, `rowCO2`, `rowCO2_LUC` → NoReported | NZ-only policy markets |
| 5 | `primary_energy_map.csv` / `primary_energy_map_v9.1.rda` | `bio-ceiling CCS` → NoReported | NZ-only |
| 6 | `inst/extdata/mappings/GCAM9.1/CO2market_new.csv`, `data/co2_market_v9.1.rda` | `rowCO2` → 31 non-Korea regions | rest-of-world carbon price was reported as 0 |
| 7 | `inst/extdata/mappings/GCAM9.1/ag_demand_map.csv`, `data/ag_demand_map_v9.1.rda` | `bio-ceiling` / `regional biomass` → NoReported | `debug.R` has its `ignore` argument commented out (§5) |
| 8 | `R/functions.R` | `is_ignored()` helper; two `grepl(paste(ignore.global))` filters replaced | empty `ignore` pattern matched every CO2 market → zero carbon prices (§5b) |

Not changed: `debug.R` logic (only paths; its `ignore` line is commented out, §5), `inst/extdata/saveDataFiles_GCAM9.1.R` (recommended:
add explicit `col_types`, see §4), `en_demand_price_map.csv` (see the `delivered coal` note in §4).
Every "BEFORE" copy of a touched CSV/`.rda` is in `Error_Log/`.
