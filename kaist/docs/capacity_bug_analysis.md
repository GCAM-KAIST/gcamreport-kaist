# Capacity|Electricity Bug in gcamreport

**Audience:** KAIST lab members who work with the gcamreport pipeline.
**Goal:** Explain why `Capacity|Electricity` values from the upstream
gcamreport package were wrong for our KMIP runs, and how the KAIST fork
works around it in `kaist/step2_process_data.R`.

This is internal lab notes. A clean version of this analysis is also being
prepared as a PR to `bc3LC/gcamreport`.

## TL;DR

The upstream `gcamreport` package builds the capacity factor (CF) used in
`Capacity|Electricity` from two sources combined with `bind_rows`:
1. `cf_rgn` — regional CF for renewables (per region + technology).
2. `cf_iea` — a single global CF derived from IEA 2020 capacity and GCAM
   2020 generation, then copied to every region.

The two get merged into one table. After the merge, the same
`(region, technology, vintage)` row often appears twice. A later
interpolation step averages the duplicates, which:
- Pulls renewable CF away from the correct `cf_rgn` value.
- Replaces fossil CF (~0.80–0.85 in `cf_gcam`) with `cf_iea`
  (~0.50–0.60), which makes capacity for coal and gas look much larger
  than it should.

Our fix in `step2_process_data.R` ignores the upstream `Capacity|Electricity`
values and recomputes them from `elec gen by gen tech and cooling tech and vintage`,
using explicit per-vintage CF lookups.

## How gcamreport computes capacity (current code)

The relevant code lives in `R/functions.R` and runs in this order:

1. **`get_cf_iea_tmp()`** (≈ line 5195 in current `kaist-workflow` HEAD)
   - Reads `iea_capacity` (IEA 2020 installed capacity) and the
     corresponding GCAM 2020 secondary energy.
   - Computes `cf = EJ / (capacity * 8760 * EJ_to_GWh)` once per
     technology.
   - Copies the single resulting CF to **all** regions and **all**
     vintages from 1990 onward.
   - The CF is labelled "USA" in the table, but it is actually the same
     for every region.

2. **`get_elec_cf_tmp()`** (≈ line 5272)
   - Starts from `cf_gcam` (global default CF, one value per technology).
   - Replaces values for renewables with `cf_rgn` where available.
   - Then calls `dplyr::bind_rows(cf_iea_filteredReg)` and appends the
     IEA-derived CF rows on top.
   - Finally, `tidyr::complete()` fills missing vintages and
     `approx_fun()` interpolates.
   - **Bug surface:** for technologies and regions that already have a
     `cf_rgn` value, the `bind_rows` adds a second row at the same
     `(technology, region, vintage)` key with the IEA-derived value.
     The downstream interpolation does not deduplicate; it treats the two
     points as two valid samples of the same vintage and averages them.

3. **`get_elec_capacity_tot()`** (≈ line 5328)
   - For each scenario, region, technology, and vintage, computes
     `capacity_gw = generation_EJ / (cf * 8760 * EJ_to_GWh)` using the
     blended `elec_cf` table above.
   - Sums across vintages.

## What the bug looks like on real data

A simplified version of the duplicate situation that triggers the
averaging is in `kaist/diagnostics/cf_debug.R` Section 3 (only on the
`kaist-workflow` branch). The script builds two rows for
`(wind, South Korea, 2030)`:

| source   | cf   |
|----------|------|
| cf_rgn   | 0.23 |
| cf_iea   | 0.15 |

After `bind_rows` + `approx_fun`, the effective CF at 2030 becomes
≈ 0.19 instead of 0.23. The capacity formula
`capacity = generation / (cf * 8760 * EJ_to_GWh)` then over-estimates
capacity by `0.23 / 0.19 ≈ 21%`.

For fossil fuels the direction is opposite and the magnitude is larger.
`cf_gcam` says coal (conv pul) is 0.85 globally; `cf_iea` for coal is
roughly 0.55 because IEA's 2020 capacity includes a lot of underused
plants in some regions. After the blend, coal CF used by gcamreport is
near 0.70, so reported capacity is too high by ~20%. South Korea coal
capacity comes out clearly larger than KMIP reference values.

## Korea-specific impact

- Coal, gas, refined liquids: capacity over-estimated by ~15–25%.
- Wind, PV: capacity off by a few percent, direction depends on year.
- Nuclear (`Gen_II_LWR`, `Gen_III`): CF averaged below 0.81 → capacity
  too high.

The Gen_III_Korea technology is a separate issue (it is missing from the
upstream `Primary Energy|Nuclear` aggregation). That is documented in
`kaist/Gen_III_Korea_bypass_evidence.md`.

## Our workaround in step2_process_data.R

See `kaist/step2_process_data.R`, section header
`Recalculate Capacity|Electricity using vintage-based calculation`
(currently around line 216 in that file).

The idea is to skip the upstream CF table and rebuild capacity from raw
vintage-level generation:

1. Run the GCAM query `elec gen by gen tech and cooling tech and vintage`.
   The result has one row per `(scenario, region, technology, vintage, year)`.
2. Sum across cooling-technology variants (`dry cooling`, `recirculating`,
   `once through`, `seawater`, `none`) for each vintage.
3. Look up CF per vintage with this priority:
   - `cf_rgn_v7.0` if `(region, technology)` has a value (renewables).
   - else `cf_gcam_v7.0` `2100` column (global default).
   - else a Korea-specific override hard-coded in the script (nuclear,
     coal, gas, oil, biomass; values come from KMIP reference data).
4. Compute `capacity_gw = generation_EJ / (cf * 8760 * 3.6e-6)` per vintage.
5. Sum capacities across all vintages of the same technology.
6. Overwrite the matching `Capacity|Electricity|...` rows in the report.

The block also writes a debug summary showing, for South Korea 2050:
- Which CF was used for each technology.
- Whether the back-calculated generation matches the original generation
  (sanity check that nothing was double-counted).

## Verifying the workaround

After running step1 then step2, the script prints two tables:

```
=== CF values used for South Korea (scenario: ...) ===
=== Verification: Generation back-calculation (South Korea, 2050) ===
```

In the second table, `diff_pct` between original and back-calculated
generation should be effectively zero (< 0.01%). A larger value means the
CF lookup missed some technology and that row was skipped.

If you want to compare to the **un-fixed** upstream output, comment out
the section in `step2_process_data.R` and rerun. The numbers for
coal / gas / nuclear capacity will jump up; that is the bug.

## What the upstream PR should change

A minimal patch to `R/functions.R`:

- In `get_elec_cf_tmp()`, remove duplicates **before** interpolation.
  Concretely: after `dplyr::bind_rows(cf_iea_filteredReg)`, drop rows
  where the same `(region, technology, vintage)` already came from
  `cf_rgn` or `cf_gcam`. Keep `cf_iea` only as a fallback for vintages
  before 2020 where no `cf_gcam` / `cf_rgn` value applies.
- Alternatively, scope `cf_iea` to historical vintages only and use
  `cf_gcam` / `cf_rgn` for projection years.

The choice between those two is best made with the bc3LC maintainer
(Claudia / klau506) since either changes the semantics of `cf_iea`.

## Second bug — `conv_EJ_GW` ignores the caller's `GCAM_version`

Found while running step1 against GCAM 7.0 after the upstream merge.

`conv_EJ_GW()` is defined in `R/functions.R` (around line 716) with a
hard-coded default:

```r
conv_EJ_GW <- function(data, cf, EJ, GCAM_version = "v7.1") { ... }
```

Inside `get_elec_capacity_tot()` the function is called four times
(around lines 5357, 5437, 5496, 5555) **without passing
`GCAM_version`**:

```r
... %>%
  conv_EJ_GW() %>%
  ...
```

So even when the caller of `get_elec_capacity_tot` sets
`GCAM_version = "v7.0"`, the inner `conv_EJ_GW` call falls back to the
v7.1 default and tries to load `convert_v7.1` via `get(... envir =
asNamespace("gcamreport"))`. If `convert_v7.1.rda` does not exist locally
(e.g. you only generated v7.0 rda files), step1 fails with:

```
Error in `dplyr::mutate()`:
ℹ In argument: `gw = `/`(...)`.
Caused by error in `get()`:
! object 'convert_v7.1' not found
```

This is purely a version-propagation bug. The numerical impact is small
because `convert_*` constants (`hr_per_yr`, `EJ_to_GWh`, ...) are
identical across versions, but the missing-object crash blocks any
non-v7.1 run.

### Local workaround

Generate the v7.1 rda alongside v7.0:

```r
source("inst/extdata/saveDataFiles_GCAM7.1.R")
```

The v7.1 rda's get used only for the constants table; the result of
step1 is the same as a clean v7.0 run.

### Proposed upstream patch

Pass `GCAM_version` through at each call site inside
`get_elec_capacity_tot` (and any other function that has the same
pattern). One-line change per call:

```r
... %>%
  conv_EJ_GW(GCAM_version = GCAM_version) %>%
  ...
```

This is small enough to bundle into the same PR as the `cf_iea`
dedup fix, since both live in the same `get_elec_capacity_tot` /
`get_elec_cf_tmp` area of `R/functions.R`. Mention both in the PR
description.

## Related files in this repo

- `R/functions.R` — buggy code lives here (`get_cf_iea_tmp`, `get_elec_cf_tmp`,
  `get_elec_capacity_tot`).
- `kaist/step2_process_data.R` — vintage-based recalculation that
  bypasses the bug for KMIP runs.
- `kaist/Gen_III_Korea_bypass_evidence.md` — related nuclear-specific
  issue, separate from the CF bug.
- Diagnostic / debug scripts (`kaist/diagnostics/cf_debug.R`,
  `debug_capacity_calc.R`, `check_cf_reverse.R`) live on the
  `kaist-workflow` branch of this repo.
