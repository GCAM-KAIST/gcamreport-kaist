# GCAM 9.1 Development Error Log

This document records errors found while adapting `gcamreport` to GCAM 9.1.
Each entry separates the observed error from its likely cause and the next
diagnostic step. The warnings below are retained as raw output because they
may help reproduce the failure.

## Current status

- The package code now uses the version key `v9.1`.
- GCAM 9.1 mappings, query definitions, templates, and conversion data are
  prepared under `inst/extdata`.
- The generated package data must be rebuilt before `available_regions()`,
  `available_variables()`, or `generate_report()` can use `v9.1`.
- Use `v9.1` consistently. `v.9.1` is a different key and will not match
  objects such as `reg_cont_v9.1`.

To rebuild the package data from the source mappings:

```r
setwd("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport_temp")
source("inst/extdata/saveDataFiles_constants.R")
source("inst/extdata/saveDataFiles_GCAM9.1.R")
devtools::load_all(".", reset = TRUE)
```

Basic checks:

```r
"v9.1" %in% available_GCAM_versions
available_regions(print = FALSE, GCAM_version = "v9.1")
available_variables(print = FALSE, GCAM_version = "v9.1")
```


## 1) Mapping mismatch when processing GCAM 9.1 with v8.2 mappings

### Symptom

GCAM 9.1 output was initially processed with the v8.2 mapping tables. The
`ag_price_map_v8.2` table does not contain the GCAM 9.1 residential appliance
names, so the strict join fails.

```text
Error in left_join_strict(., get(paste("ag_price_map", GCAM_version, sep = "_"),  : 
  Error: Some rows in the left dataset do not have matching keys in the right dataset. Type `left_join_strict_details` to see the full log. Some of the rows that the mapping ag_price_map_v8.2 miss are:
# A tibble: 10 × 1
   sector                         
   <chr>                          
 1 resid clothes dryers modern_d1 
 2 resid clothes dryers modern_d10
 3 resid clothes dryers modern_d2 
 4 resid clothes dryers modern_d3 
 5 resid clothes dryers modern_d4 
 6 resid clothes dryers modern_d5 
 7 resid clothes dryers modern_d6 
 8 resid clothes dryers modern_d7 
 9 resid clothes dryers modern_d8 
10 resid clothes dryers modern_d9 
In addition: 
There were 50 or more warnings (use warnings() to see the first 50)
```

### Interpretation

This is a version-data mismatch, not evidence that `left_join_strict()` is
incorrect. The strict join intentionally stops when a GCAM name has no
standardized mapping. Set `GCAM_version = "v9.1"` only after the v9.1 package
objects have been generated, and then add or review any remaining unmapped
names in the v9.1 source mappings.

The warnings that follow are the original run output. Many of the
`clobber is false` messages occur while an existing project is being reused;
they should be interpreted separately from the mapping error above.

> warnings()
Warning messages:
1: In create_project(db_path = db_path, db_name = db_name,  ... :
  CO2 prices query is empty!
2: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / CO2 emissions by region as clobber is false.
3: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / GDP MER by region as clobber is false.
4: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / GDP per capita PPP by region as clobber is false.
5: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / National Account as clobber is false.
6: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / building service costs as clobber is false.
7: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / building service output by service as clobber is false.
8: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / building total final energy by service as clobber is false.
9: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / costs of transport modes as clobber is false.
10: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / food demand as clobber is false.
11: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / food demand prices as clobber is false.
12: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / food consumption by type (general) as clobber is false.
13: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / food consumption by type (specific) as clobber is false.
14: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / population by region as clobber is false.
15: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / subregional population as clobber is false.
16: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / subregional income as clobber is false.
17: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / primary energy consumption with CCS by region (direct equivalent) as clobber is false.
18: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / resource production as clobber is false.
19: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / resource production by tech and vintage as clobber is false.
20: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / refined liquids production by cooling tech and vintage as clobber is false.
21: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / hydrogen production by cooling tech and vintage as clobber is false.
22: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / regional primary energy prices as clobber is false.
23: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / elec gen by subsector as clobber is false.
24: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / elec gen by gen tech as clobber is false.
25: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / elec gen by gen tech and cooling tech and vintage as clobber is false.
26: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / refined liquids production by region as clobber is false.
27: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / refined liquids production by tech as clobber is false.
28: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / hydrogen production by tech as clobber is false.
29: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / gas production by tech as clobber is false.
30: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / district heat production by subsector (fuel) as clobber is false.
31: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / final energy consumption by sector and fuel as clobber is false.
32: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / building floorspace as clobber is false.
33: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / industry primary output by sector as clobber is false.
34: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / industry final energy by tech and fuel as clobber is false.
35: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / transport final energy by mode and fuel as clobber is false.
36: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / fuel prices to transport as clobber is false.
37: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / elec td inputs and outputs as clobber is false.
38: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / regional biomass consumption as clobber is false.
39: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / ag production by crop type as clobber is false.
40: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / ag export to the world center (USA) (Intl. Armington competition) as clobber is false.
41: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / ag import vs. domestic supply (Regional Armington competition) as clobber is false.
42: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / meat and dairy production by type as clobber is false.
43: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / demand balances by crop commodity as clobber is false.
44: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / demand balances by meat and dairy commodity as clobber is false.
45: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / ammonia and N fertilizer prices as clobber is false.
46: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / fertilizer consumption by region as clobber is false.
47: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / purpose-grown biomass production as clobber is false.
48: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / residue biomass production as clobber is false.
49: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / MSW production as clobber is false.
50: In rgcam::mergeProjects(prj_name, list(prj, prj_tmp),  ... :
  Skipping data in Reference / LUC emissions by region as clobber is false.