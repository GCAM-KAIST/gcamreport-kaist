################################################################################
# helpers.R -- small utilities shared by the step2 modules and orchestrator
################################################################################

# Names of the 4-digit year columns of a report data frame ("2005", "2010", ...)
year_cols <- function(df) {
  names(df)[grepl("^[0-9]{4}$", names(df))]
}

# Keep only one region and the years in [start_year, final_year].
# Returns a plain data.frame (modules assign into rows by index).
filter_region_years <- function(data, region, start_year, final_year) {
  yc <- year_cols(data)
  years_to_remove <- yc[as.numeric(yc) < start_year | as.numeric(yc) > final_year]
  out <- data %>%
    select(-all_of(years_to_remove)) %>%
    filter(Region == region)
  as.data.frame(out)
}

# Load one of the package data objects (data/<prefix>_v<version>.rda) and
# return it. The object INSIDE the rda carries the same version suffix as the
# file name, so both are built from `prefix` and `version`. Using this instead
# of a hardcoded load("data/cf_rgn_v7.0.rda") means a GCAM version switch is
# just the `version_number` line in kaist/config.R.
load_gcam_rda <- function(prefix, version = version_number) {
  obj_name <- paste0(prefix, "_v", version)
  path <- file.path(getwd(), "data", paste0(obj_name, ".rda"))
  if (!file.exists(path)) stop("Data file not found: ", path)
  env <- new.env()
  load(path, envir = env)
  get(obj_name, envir = env)
}

# TRUE when verbose debug output is enabled (verbose_debug in kaist/config.R).
# Modules wrap their diagnostic tables in `if (debug_on()) { ... }`.
debug_on <- function() {
  isTRUE(get0("verbose_debug", ifnotfound = FALSE))
}

# Overwrite each parent row with the column sums of its child rows, per
# (Scenario, Region) combination that has child rows. `parent_children` is a
# named list: names are parent Variable strings, values are character vectors
# of child Variable strings.
sum_children_into_parents <- function(data, parent_children) {
  yc <- year_cols(data)

  for (parent_var in names(parent_children)) {
    child_vars <- parent_children[[parent_var]]

    child_idx <- which(data$Variable %in% child_vars)
    parent_idx <- which(data$Variable == parent_var)
    if (length(child_idx) == 0 || length(parent_idx) == 0) next

    for (scen in unique(data$Scenario[child_idx])) {
      for (rgn in unique(data$Region[child_idx])) {
        scen_child_idx <- child_idx[data$Scenario[child_idx] == scen & data$Region[child_idx] == rgn]
        scen_parent_idx <- parent_idx[data$Scenario[parent_idx] == scen & data$Region[parent_idx] == rgn]

        if (length(scen_parent_idx) > 0 && length(scen_child_idx) > 0) {
          child_sum <- colSums(data[scen_child_idx, yc, drop = FALSE], na.rm = TRUE)
          data[scen_parent_idx[1], yc] <- child_sum
        }
      }
    }
  }

  data
}

# MT 2020 steel values used by b3 and b6 (ktoe, ktoe, Mt CO2eq).
# Read from the reference workbook if it exists, else use the constants.
mt_steel_reference_2020 <- function(path = get0("mt_reference_path", ifnotfound = "")) {
  ref <- list(coal_fuel = 11008.16016, coal_feedstock = 15400.84953,
              process_co2 = 29.64761356,
              source = "built-in constants (MT S1 2020, KMIP2025 reference workbook)")
  if (!nzchar(path) || !file.exists(path)) return(ref)

  pre  <- "Final Energy|Industry|Manufacturing|Iron and Steel|Coal|"
  vars <- c(coal_fuel      = paste0(pre, "Fuel"),
            coal_feedstock = paste0(pre, "Feedstock"),
            process_co2    = "Emissions|GHGs|Non-Energy|Industrial Process|Manufacturing|Iron and Steel")
  mt <- readxl::read_excel(path, sheet = "data") %>%
    filter(Model == "MT", trimws(Scenario) == "S1", Variable %in% vars)
  for (nm in names(vars)) {
    v <- mt %>% filter(Variable == vars[[nm]])
    if (nrow(v) != 1) stop("MT reference: expected 1 MT/S1 row for ", vars[[nm]], ", got ", nrow(v))
    ref[[nm]] <- as.numeric(v[["2020"]])
  }
  ref$source <- basename(path)
  ref
}
