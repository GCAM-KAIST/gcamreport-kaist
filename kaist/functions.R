################################################################################
# KAIST helper functions
#
# Custom functions + data overrides for the kaist/ pipeline. Kept here (not in
# R/ or inst/) so the package source stays byte-identical to upstream gcamreport
# and `git merge upstream/gcam-core` never conflicts.
#
# Sourced automatically from kaist/config.R, so every step file has these
# available after `source(".../kaist/config.R")`.
#
# --- Why patch_gcam_data() exists --------------------------------------------
# KAIST runs GCAM with extra policy markets (bio-ceiling, irnstl-ceiling, ...)
# and a Korea-only nuclear tech (Gen_III_Korea). gcamreport's stock mapping
# tables do not know about those, so historically we edited
#   inst/extdata/saveDataFiles_GCAM7.0.R
# to add the missing rows / CF overrides before it writes data/*.rda.
#
# upstream changes that file often (≈monthly, all version files at once), so
# editing it caused recurring merge conflicts. Instead we now keep that file at
# 100% upstream and re-apply the SAME modifications at runtime, here, by
# rewriting the built data/*.rda objects. patch_gcam_data() is called at the top
# of step1 / step2 (before devtools::load_all), so generate_report() and the
# step2 calculations see the KAIST-modified data.
#
# --- Moving to a new GCAM version (v8.2, v9, ...) -----------------------------
# Add a new entry to kaist_overrides keyed by the GCAM_version string, e.g.
#   kaist_overrides[["v8.2"]] <- list(...)
# then call patch_gcam_data("v8.2"). The applier code below stays the same; only
# the per-version values (tech names, CF values, dropped variables) change.
# Review each block against the new version's mapping CSV column names.
################################################################################


# available_variables_with_units --------------------------------------------
# Like gcamreport::available_variables(), but returns each variable together
# with its unit. Reads the bundled template_v7.x via the loaded gcamreport
# namespace, so it only works after devtools::load_all(".") in a step file.
available_variables_with_units <- function(print = TRUE, GCAM_version = "v7.1") {
  Internal_variable <- Variable <- Unit <- NULL

  av_var <- get(paste("template", GCAM_version, sep = "_"),
                envir = asNamespace("gcamreport")) %>%
    dplyr::filter(!is.na(Internal_variable) & Internal_variable != "") %>%
    dplyr::select(Variable, Unit) %>%
    dplyr::distinct()

  if (print) {
    for (i in seq_len(nrow(av_var))) {
      cat(av_var$Variable[i], " (", av_var$Unit[i], ")\n", sep = "")
    }
  }

  return(av_var)
}


# add_korea_cf ---------------------------------------------------------------
# Append South Korea conventional-technology capacity factors (KMIP reference
# values) to a cf_rgn table. Upstream cf_rgn ships renewables only; the step2
# vintage-based capacity recalculation needs these conventional CFs too.
# Idempotent: drops any existing (region, technology, year) rows before binding.
# Written pipe-free so it can run before dplyr is attached (i.e. before load_all).
add_korea_cf <- function(cf_rgn) {
  korea_cf <- tidyr::crossing(
    tibble::tribble(
      ~subsector,         ~stub.technology,              ~capacity.factor,
      # Coal
      "coal",             "coal (conv pul)",             0.635,
      "coal",             "coal (conv pul CCS)",         0.635,
      "coal",             "coal (IGCC)",                 0.635,
      "coal",             "coal (IGCC CCS)",             0.635,
      # Gas
      "gas",              "gas (CC)",                    0.50,
      "gas",              "gas (CC CCS)",                0.50,
      "gas",              "gas (steam/CT)",              0.50,
      # Hydro
      "hydro",            "hydro",                       0.084,
      # Nuclear (Gen_III_Korea is a Korea-only tech defined in cf_gcam)
      "nuclear",          "Gen_III",                     0.8144,
      "nuclear",          "Gen_III_Korea",               0.8144,
      "nuclear",          "Gen_II_LWR",                  0.8144,
      # Refined liquids (oil-fired)
      "refined liquids",  "refined liquids (CC)",        0.76,
      "refined liquids",  "refined liquids (CC CCS)",    0.76,
      "refined liquids",  "refined liquids (steam/CT)",  0.76,
      # Biomass
      "biomass",          "biomass (conv)",              0.80,
      "biomass",          "biomass (conv CCS)",          0.80,
      "biomass",          "biomass (IGCC)",              0.80,
      "biomass",          "biomass (IGCC CCS)",          0.80,
      # Solar CSP (with and without storage)
      "CSP",              "CSP",                         0.20,
      "CSP",              "CSP_storage",                 0.20
    ),
    year = c(2005, 2010, 2015, 2020, 2025, 2030, 2035, 2040,
             2045, 2050, 2055, 2060, 2070, 2080, 2090, 2100)
  )
  korea_cf <- dplyr::mutate(korea_cf, region = "South Korea", supplysector = "electricity")

  cf_rgn <- dplyr::anti_join(cf_rgn, korea_cf,
                             by = c("region", "stub.technology", "year"))
  dplyr::bind_rows(cf_rgn, korea_cf)
}


# kaist_overrides ------------------------------------------------------------
# Declarative list of the KAIST data modifications, keyed by GCAM_version.
# These mirror what used to live in inst/extdata/saveDataFiles_GCAM7.0.R.
#
# For the gathered mapping tables, gcamreport's gather_map() turns the wide
# var1/var2/... columns into a single `var` column, so the rows below are given
# in that gathered shape (one row per non-empty var value).
kaist_overrides <- list(
  "v7.0" = list(

    # Gathered mapping tables: rows to add. `key` = columns used to detect and
    # replace an already-present row (idempotent re-runs).
    map_rows = list(
      carbon_seq_tech_map = list(
        rows = tibble::tibble(
          sector    = "chemical feedstocks",
          technology = c("coal", "gas"),
          unit_conv = "1",
          var       = "NoReported"
        ),
        key = c("sector", "technology", "var")
      ),
      primary_energy_map = list(
        rows = tibble::tibble(
          fuel = c("bio-ceiling", "coal-ceiling", "irnstl-ceiling",
                   "uranium", "bio-ceiling CCS", "irnstl_ceiling_EAF"),
          unit_conv = 1,
          var = "NoReported"
        ),
        key = c("fuel", "var")
      ),
      final_energy_map = list(
        rows = tibble::tibble(
          sector = "iron and steel",
          input  = c("irnstl-ceiling", "irnstl_ceiling_EAF"),
          unit_conv = 1,
          var = "NoReported"
        ),
        key = c("sector", "input", "var")
      ),
      energy_price_map = list(
        rows = tibble::tibble(
          market = c("SolGeneration-Floor", "WindOff_Generation-Ceiling",
                     "WindOn_Generation-Ceiling", "bio-ceiling", "coal-ceiling",
                     "dac-ceiling", "imported H2", "irnstl-ceiling",
                     "irnstl_ceiling_EAF", "CO2_Kor", "rowbio-ceiling",
                     "rowCO2", "rowCO2_LUC"),
          unit_conv = 1,
          var = "NoReported"
        ),
        key = c("market", "var")
      ),
      # secondary_energy_map and capacity_map are both built from capacity_map.csv
      # and get the same Gen_III_Korea entry (var1 + var2 -> two gathered rows).
      secondary_energy_map = list(
        rows = tibble::tibble(
          output = "electricity",
          subsector = "nuclear",
          technology = "Gen_III_Korea",
          unit_conv = 1,
          var = c("Secondary Energy|Electricity",
                  "Secondary Energy|Electricity|Nuclear")
        ),
        key = c("output", "subsector", "technology", "var")
      ),
      capacity_map = list(
        rows = tibble::tibble(
          output = "electricity",
          subsector = "nuclear",
          technology = "Gen_III_Korea",
          unit_conv = 1,
          var = c("Secondary Energy|Electricity",
                  "Secondary Energy|Electricity|Nuclear")
        ),
        key = c("output", "subsector", "technology", "var")
      )
    ),

    # Gathered mapping tables: copy all rows of one (sector, subsector) key to
    # a new key. KAIST DBs report resid heating/others without the
    # modern/TradBio split used upstream.
    map_copy_rows = list(
      nonco2_emis_sector_map = tibble::tribble(
        ~from_sector,            ~from_subsector,       ~to_sector,      ~to_subsector,
        "resid heating modern",  "biomass",             "resid heating", "biomass",
        "resid heating TradBio", "traditional biomass", "resid heating", "traditional biomass",
        "resid others modern",   "biomass",             "resid others",  "biomass",
        "resid others TradBio",  "traditional biomass", "resid others",  "traditional biomass"
      )
    ),

    # ag_demand_map: upstream has no !is.na(input) filter, so drop NA-input rows
    # (they create NA sectors downstream) and add the bio-ceiling entries.
    ag_demand_drop_na_input = TRUE,
    ag_demand_rows = tibble::tibble(
      input  = c("bio-ceiling", "bio-ceiling CCS"),
      sector = "regional biomass",
      unit_conv = 1,
      var = "NoReported"
    ),
    ag_demand_key = c("input", "sector", "var"),

    # cf_gcam (NOT gathered): global default capacity factors. Add the Korea
    # nuclear tech and an offshore-wind default. Only 1971 and 2100 are set, as
    # in the original; other year columns stay NA.
    cf_gcam_rows = tibble::tibble(
      supplysector = "electricity",
      subsector    = c("nuclear", "wind"),
      technology   = c("Gen_III_Korea", "wind_offshore"),
      `1971`       = c(0.9, 0.4),
      `2100`       = c(0.9, 0.4)
    ),
    cf_gcam_key = c("supplysector", "subsector", "technology"),

    # cf_rgn (NOT gathered): South Korea renewable CF overrides (technology ->
    # capacity.factor). Korea conventional-tech CFs are added by add_korea_cf().
    cf_rgn_sk_renewable = c(
      rooftop_pv    = 0.154,
      PV            = 0.154,
      PV_storage    = 0.154,
      wind          = 0.23,
      wind_storage  = 0.23,
      wind_offshore = 0.29
    ),

    # capital_gcam (NOT gathered): Gen_III_Korea reuses Gen_III capital costs.
    capital_copy_tech = c(from = "Gen_III", to = "Gen_III_Korea"),

    # template (NOT gathered): drop these Internal_variable groups.
    template_drop = c("income_clean", "consumption_hh_clean",
                      "iron_steel_map", "ag_trade", "trade_clean")
  )
)


# .bind_kaist_rows -----------------------------------------------------------
# Add `new` rows to `df`, coercing shared columns to df's types and removing any
# existing rows that match on `key` first (so repeated patching is idempotent).
.bind_kaist_rows <- function(df, new, key) {
  for (cn in intersect(names(df), names(new))) {
    cls <- class(df[[cn]])[1]
    if (cls %in% c("numeric", "integer", "double")) {
      new[[cn]] <- as.numeric(new[[cn]])
    } else if (cls == "character") {
      new[[cn]] <- as.character(new[[cn]])
    } else if (cls == "logical") {
      new[[cn]] <- as.logical(new[[cn]])
    }
  }
  keep_key <- intersect(key, intersect(names(df), names(new)))
  if (length(keep_key) > 0) {
    new_keys <- dplyr::distinct(dplyr::select(new, dplyr::all_of(keep_key)))
    df <- dplyr::anti_join(df, new_keys, by = keep_key)
  }
  dplyr::bind_rows(df, new)
}


# patch_gcam_data ------------------------------------------------------------
# Re-apply the KAIST data overrides to the built package data objects on disk
# (data/<name>_<version>.rda). Call this BEFORE devtools::load_all() so the
# patched objects are what gets loaded into the gcamreport namespace.
#
# `version` is the GCAM_version string, e.g. "v7.0". Idempotent: safe to call on
# already-patched data, and on either upstream-fresh or previously-customized
# .rda files.
patch_gcam_data <- function(version = "v7.0") {
  ov <- kaist_overrides[[version]]
  if (is.null(ov)) {
    warning(sprintf(
      "patch_gcam_data: no KAIST overrides defined for version '%s' -- data left unchanged. Add a kaist_overrides[['%s']] block in kaist/functions.R.",
      version, version))
    return(invisible(FALSE))
  }

  data_dir <- file.path(getwd(), "data")
  obj_file <- function(short) file.path(data_dir, paste0(short, "_", version, ".rda"))

  load_obj <- function(short) {
    f <- obj_file(short)
    if (!file.exists(f)) {
      warning(sprintf("patch_gcam_data: %s not found -- skipping. Run inst/extdata/saveDataFiles_GCAM*.R first.", f))
      return(NULL)
    }
    e <- new.env()
    load(f, envir = e)
    e[[paste0(short, "_", version)]]
  }
  save_obj <- function(short, obj) {
    nm <- paste0(short, "_", version)
    assign(nm, obj)
    save(list = nm, file = obj_file(short))
  }

  patched <- character(0)

  # 1. Gathered mapping tables: add rows.
  for (short in names(ov$map_rows)) {
    obj <- load_obj(short)
    if (is.null(obj)) next
    spec <- ov$map_rows[[short]]
    obj <- .bind_kaist_rows(obj, spec$rows, spec$key)
    save_obj(short, obj)
    patched <- c(patched, short)
  }

  # 1b. Gathered mapping tables: copy rows to a new (sector, subsector) key.
  for (short in names(ov$map_copy_rows)) {
    obj <- load_obj(short)
    if (is.null(obj)) next
    spec <- ov$map_copy_rows[[short]]
    new <- dplyr::bind_rows(lapply(seq_len(nrow(spec)), function(i) {
      dplyr::mutate(
        dplyr::filter(obj, sector == spec$from_sector[i], subsector == spec$from_subsector[i]),
        sector = spec$to_sector[i], subsector = spec$to_subsector[i])
    }))
    obj <- .bind_kaist_rows(obj, new, c("sector", "subsector", "ghg", "var"))
    save_obj(short, obj)
    patched <- c(patched, short)
  }

  # 2. ag_demand_map: drop NA-input rows + add bio-ceiling rows.
  ag <- load_obj("ag_demand_map")
  if (!is.null(ag)) {
    if (isTRUE(ov$ag_demand_drop_na_input)) {
      ag <- dplyr::filter(ag, !is.na(input))
    }
    ag <- .bind_kaist_rows(ag, ov$ag_demand_rows, ov$ag_demand_key)
    save_obj("ag_demand_map", ag)
    patched <- c(patched, "ag_demand_map")
  }

  # 3. cf_gcam: add Gen_III_Korea / wind_offshore default CFs.
  cg <- load_obj("cf_gcam")
  if (!is.null(cg)) {
    cg <- .bind_kaist_rows(cg, ov$cf_gcam_rows, ov$cf_gcam_key)
    save_obj("cf_gcam", cg)
    patched <- c(patched, "cf_gcam")
  }

  # 4. cf_rgn: South Korea renewable overrides + Korea conventional CFs.
  cr <- load_obj("cf_rgn")
  if (!is.null(cr)) {
    for (tech in names(ov$cf_rgn_sk_renewable)) {
      sel <- cr$region == "South Korea" & cr$stub.technology == tech
      cr$capacity.factor[sel] <- ov$cf_rgn_sk_renewable[[tech]]
    }
    cr <- add_korea_cf(cr)
    save_obj("cf_rgn", cr)
    patched <- c(patched, "cf_rgn")
  }

  # 5. capital_gcam: copy Gen_III capital rows to Gen_III_Korea.
  cap <- load_obj("capital_gcam")
  if (!is.null(cap) && !is.null(ov$capital_copy_tech)) {
    from <- ov$capital_copy_tech[["from"]]
    to   <- ov$capital_copy_tech[["to"]]
    cap <- dplyr::filter(cap, technology != to)                 # idempotent
    extra <- dplyr::mutate(dplyr::filter(cap, technology == from), technology = to)
    cap <- dplyr::bind_rows(cap, extra)
    save_obj("capital_gcam", cap)
    patched <- c(patched, "capital_gcam")
  }

  # 6. template: drop KAIST-excluded variable groups.
  tpl <- load_obj("template")
  if (!is.null(tpl)) {
    tpl <- dplyr::filter(tpl, !Internal_variable %in% ov$template_drop)
    save_obj("template", tpl)
    patched <- c(patched, "template")
  }

  message(sprintf("patch_gcam_data(%s): patched %d data object(s): %s",
                  version, length(patched), paste(patched, collapse = ", ")))
  invisible(TRUE)
}
