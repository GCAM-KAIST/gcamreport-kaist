# GCAM Query Browser (Full Edition): Unified Access to All GCAM Output

## Background: The Existing Workflow

### How GCAM Output Was Accessed Before

GCAM (Global Change Analysis Model) stores simulation results in a **BaseX XML database**. To extract data, two tools exist:

1. **ModelInterface** (Java GUI): Users manually select queries from a tree of **335 available queries**, choose regions and scenarios, click "Run Query", and view results one at a time. No programmatic access.

2. **gcamreport** (R package): An automated pipeline using the `rgcam` R library that generates IAMC-format reports. However, it only executes **76 out of 335** queries — the subset needed for IAMC variable generation.

### The 5-Step KAIST-KMIP Workflow

```
Step 1: generate_report.R  → Query DB via rgcam → .dat cache + .xlsx
Step 2: process_data.R     → Post-processing (Korea-specific fixes) → .csv
Step 3: create_mapping.R   → Auto-match GCAM vars to KMIP template
Step 4: fill_template.R    → Apply mapping + unit conversion → final output
Step 5: verification.qmd   → Compare automated vs manual reporting
```

### Pain Points

| Problem                          | Detail                                                                                                   |
| -------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **Exact name required**          | Must type full query names (e.g., `"primary energy consumption with CCS by region (direct equivalent)"`) |
| **Heavy loading every session**  | Must load `rgcam` library + ~50MB `.dat` file each time                                                  |
| **No browsable index**           | No way to see all available queries at a glance with numbered access                                     |
| **No persistent regional cache** | Region filtering done manually, results not saved                                                        |
| **Only 76/335 queries**          | gcamreport caches only queries needed for IAMC; the other 259 queries require ModelInterface GUI         |

---

## Solution: Query Browser (Full Edition)

### Architecture

```
                    ┌─────────────────────────┐
                    │  query_browser_full.R    │
                    └──────────┬──────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                 ▼
     .dat cache (76)    Main_queries.xml    BaseX DB
     (from Step 1)      (335 queries)       (live)
              │                │                 │
              ▼                ▼                 ▼
         get_query()    list_all_queries()  run_db_query()
              │                                  │
              └──────────┬───────────────────────┘
                         ▼
                  export to CSV + RDS
                         ▼
                  load_cached_full()
                  (no rgcam needed)
```

### Two Layers of Access

**Layer 1 — Cached Queries (76, instant)**
Reads from the `.dat` project file already created by Step 1. No database connection needed.

**Layer 2 — Full Queries (335, from DB)**
Parses `Main_queries.xml` with `xml2` to extract all 335 query definitions, then executes them against the live BaseX database via `rgcam::runQuery()`. Automatically uses the `.dat` cache when a query is already available there.

### Key Discovery: XML Format Incompatibility

The standard `rgcam::parse_batch_query()` function cannot parse `Main_queries.xml` because:
- gcamreport uses flat `<aQuery>` elements
- ModelInterface uses nested `<queryGroup>` hierarchy

**Solution**: Custom parsing with `xml2::xml_find_all()` using XPath to extract all query elements regardless of nesting depth:
```r
xml_find_all(xml, "//*[self::supplyDemandQuery or self::emissionsQueryBuilder
  or self::demographicsQuery or self::gdpQueryBuilder
  or self::query or self::singleQuery][@title]")
```

### Functions

| Function | Source | Purpose |
|----------|--------|---------|
| `list_queries()` | .dat cache | Display 76 cached queries with numbered index |
| `get_query(n)` | .dat cache | Retrieve cached query by number or partial name |
| `list_all_queries()` | Main_queries.xml | Display all 335 queries with category and cache indicator |
| `list_all_queries("elec")` | Main_queries.xml | Filter by keyword |
| `run_db_query(n)` | DB / cache | Run any of 335 queries (auto-uses cache if available) |
| `export_all()` | .dat cache | Export 76 cached queries to CSV + RDS |
| `export_all_from_db()` | DB + cache | Export all 335 queries to CSV + RDS |
| `load_cached_full()` | RDS file | Reload full export without rgcam |

### Usage Demo

```r
source("kaist/query_browser_full.R")

# ============================================
#   GCAM Query Browser (Full Edition)
# ============================================
# Cached (.dat):  74 queries
# Scenarios:      Ref_Con ..., 05_nzM_Adv_plus ...
# Main_queries:   335 queries (from XML)
# Database:       DB25 at C:/GCAM/gcamreport/kmip
# ============================================

# Browse all 335 queries (* = cached in .dat)
list_all_queries()
# [001]* CO2 emissions by region                    (emissions > CO2)
# [002]  primary energy consumption by region       (energy > primary energy)
# [003]* elec gen by gen tech                       (energy > electricity)
# ...

# Run a query NOT in .dat cache (directly from DB)
result <- run_db_query("resource supply curves")
# Running query [28]: resource supply curves
# Category: energy > primary energy
# (Executing against BaseX database...)
# Rows: 342

# Run by number
result <- run_db_query(10)

# Export everything and work offline
export_all_from_db()
cached <- load_cached_full()
cached[["resource supply curves"]]
```

### Output Structure

```
kmip/DB25_output/
│
└── query_export_full/                  # 335 full queries
    ├── query_index_full.csv            # Includes category & source info
    ├── all_queries_full_South_Korea.rds
    └── 001_primary_energy_consumption_by_region.csv ...
```

---

## Query Coverage Comparison

|                   | ModelInterface (GUI) | gcamreport (.dat)    | Query Browser Full        |
| ----------------- | -------------------- | -------------------- | ------------------------- |
| **Total Queries** | 335                  | 76                   | **335**                   |
| **Access Method** | Manual GUI clicks    | R code, exact names  | **Number or name search** |
|                   |                      | .dat file            | **CSV + RDS cache**       |


---

## Planned Extensions

### 1. Wide-Format (Pivot) Output

Currently, query results are in **tidy (long) format**:

| scenario | region | technology | year | value |
|----------|--------|-----------|------|-------|
| 05_nzM_Adv_plus | South Korea | coal | 2020 | 45.3 |
| 05_nzM_Adv_plus | South Korea | coal | 2025 | 38.1 |
| 05_nzM_Adv_plus | South Korea | gas | 2020 | 22.7 |

This is hard to scan visually. Planned: add a `wide = TRUE` option to `get_query()` and `run_db_query()` that pivots to **wide format** (year as columns), matching how ModelInterface displays results:

| scenario | region | technology | 2020 | 2025 | 2030 | ... |
|----------|--------|-----------|------|------|------|-----|
| 05_nzM_Adv_plus | South Korea | coal | 45.3 | 38.1 | 29.5 | ... |
| 05_nzM_Adv_plus | South Korea | gas | 22.7 | 25.4 | 21.8 | ... |

### 2. Interactive Query Explorer

Build a Shiny web app wrapper that provides:
- Searchable, sortable query table
- Click-to-view with automatic wide-format display
- Side-by-side scenario comparison
- Plot generation for time-series data

### 3. Query Diff Tool

Compare results between two scenarios or two database versions:
- Highlight cells where values differ by more than a threshold
- Generate summary statistics of divergence by sector

---

## Summary

| Before | After |
|--------|-------|
| Must type exact query names | Browse by number: `run_db_query(5)` |
| Load rgcam + .dat every session | One-time export, then `load_cached_full()` |
| Manual region filtering each time | Auto-filtered to South Korea |
| Only 76/335 queries accessible in R | **All 335 queries** via DB or cache |
| Must use ModelInterface GUI for other queries | Programmatic access to everything |
| Tidy format only | **Planned**: wide format for quick visual inspection |
