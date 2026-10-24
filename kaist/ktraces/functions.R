################################################################################
# K-TRACES data overrides (GCAM 9.1), applied in memory after kaist_overrides.
#
# The K-TRACES tables report industries that are not in the IAMC common
# definitions (Industry|Construction, Industry|Mining, Service Output|...), so
# these overrides live here and not in kaist/core: they apply only when a
# settings file sources this file (kaist/ktraces/config/*.R) and the K-TRACES
# step1 (kaist/ktraces/step1_ktraces.R) calls patch_project_data() after
# patch_gcam_data(), before inject_kaist_data(). kaist/core is not changed.
# Do not use these settings for IAMC / KMIP submissions.
################################################################################

ktraces_overrides <- list(
  "v9.1" = list(
    # Construction and mining energy use are reported by upstream inside
    # Industry|Other Sector. Their rows move (final energy and energy CO2) to
    # Industry|Construction / Industry|Mining, so Other Sector keeps the rest.
    # The fuel-combustion CO2 of `process heat cement` goes to Non-Metallic
    # Minerals (upstream: Other Sector), where its final energy already is.
    # `template = TRUE` copies the Other Sector template rows to the new branch.
    map_relabel = list(
      list(object = "final_energy_map", sectors = c("construction energy use", "construction feedstocks"),
           from = "Final Energy|Industry|Other Sector", to = "Final Energy|Industry|Construction", template = TRUE),
      list(object = "final_energy_map", sectors = "mining energy use",
           from = "Final Energy|Industry|Other Sector", to = "Final Energy|Industry|Mining", template = TRUE),
      list(object = "co2_tech_map", sectors = c("construction energy use", "construction feedstocks"),
           from = "Emissions|CO2|Energy|Demand|Industry|Other Sector",
           to = "Emissions|CO2|Energy|Demand|Industry|Construction", template = TRUE),
      list(object = "co2_tech_map", sectors = "mining energy use",
           from = "Emissions|CO2|Energy|Demand|Industry|Other Sector",
           to = "Emissions|CO2|Energy|Demand|Industry|Mining", template = TRUE),
      list(object = "co2_tech_map", sectors = "process heat cement",
           from = "Emissions|CO2|Energy|Demand|Industry|Other Sector",
           to = "Emissions|CO2|Energy|Demand|Industry|Non-Metallic Minerals", template = FALSE)
    ),

    # Service output (EJ of energy service) of the energy-service industry
    # sectors. "industry primary output by sector" already returns them; upstream
    # maps them to NoReported. Reported so that energy intensity can be computed
    # as final energy / service output.
    service_output_rows = tibble::tibble(
      sector = c("construction energy use", "construction feedstocks", "mining energy use",
                 "agricultural energy use", "other industrial energy use", "other industrial feedstocks"),
      `GCAM output unit` = "EJ",
      var = c("Service Output|Industry|Construction", "Service Output|Industry|Construction",
              "Service Output|Industry|Mining", "Service Output|Agriculture",
              "Service Output|Industry|Other Sector", "Service Output|Industry|Other Sector")),
    template_rows = tibble::tibble(
      Variable = c("Service Output|Industry|Construction", "Service Output|Industry|Mining",
                   "Service Output|Agriculture", "Service Output|Industry|Other Sector"),
      Unit = "EJ/yr", Tier = 3, Internal_variable = "industry_production_clean", Model = "GCAM 9.1")
  )
)


# patch_project_data -----------------------------------------------------------
# Called by step1_ktraces.R after patch_gcam_data(version) and before
# inject_kaist_data(). Works on .kaist_data: an object already patched by
# kaist_overrides is taken from there, otherwise it is loaded from data/.
# Idempotent: moved rows no longer match `from`, added rows are keyed.
patch_project_data <- function(version) {
  ov <- ktraces_overrides[[version]]
  if (is.null(ov)) {
    warning(sprintf("patch_project_data: no K-TRACES overrides for '%s' -- nothing applied.", version))
    return(invisible(FALSE))
  }
  get_obj <- function(short) {
    nm <- paste0(short, "_", version)
    if (exists(nm, envir = .kaist_data, inherits = FALSE)) return(get(nm, envir = .kaist_data))
    f <- gcam_rda_path(nm)
    if (!file.exists(f)) {
      warning(sprintf("patch_project_data: %s not found -- skipping.", f))
      return(NULL)
    }
    e <- new.env(); load(f, envir = e); e[[nm]]
  }
  put_obj <- function(short, obj) assign(paste0(short, "_", version), obj, envir = .kaist_data)
  patched <- character(0)

  # 1. Move the rows of the given GCAM sectors from one IAMC branch to another
  #    (prefix rename of `var`); collect the matching template rows.
  tpl_new <- NULL
  for (spec in ov$map_relabel) {
    obj <- get_obj(spec$object)
    if (is.null(obj)) next
    hit <- obj$sector %in% spec$sectors &
      (obj$var == spec$from | startsWith(obj$var, paste0(spec$from, "|")))
    obj$var[hit] <- paste0(spec$to, substring(obj$var[hit], nchar(spec$from) + 1))
    put_obj(spec$object, obj)
    patched <- c(patched, spec$object)
    if (isTRUE(spec$template)) {
      tpl <- get_obj("template")
      rows <- dplyr::filter(tpl, Variable == spec$from | startsWith(Variable, paste0(spec$from, "|")))
      rows$Variable <- paste0(spec$to, substring(rows$Variable, nchar(spec$from) + 1))
      tpl_new <- dplyr::bind_rows(tpl_new, rows)
    }
  }

  # 2. production_map: replace the NoReported rows of these sectors.
  if (!is.null(ov$service_output_rows)) {
    pm <- get_obj("production_map")
    if (!is.null(pm)) {
      pm <- dplyr::filter(pm, !(sector %in% ov$service_output_rows$sector & var == "NoReported"))
      put_obj("production_map", .bind_kaist_rows(pm, ov$service_output_rows, c("sector", "var")))
      patched <- c(patched, "production_map")
    }
  }

  # 3. template: copied branch rows + the service output rows.
  tpl_new <- dplyr::bind_rows(tpl_new, ov$template_rows)
  if (!is.null(tpl_new) && nrow(tpl_new) > 0) {
    tpl <- get_obj("template")
    if (!is.null(tpl)) {
      put_obj("template", .bind_kaist_rows(tpl, dplyr::distinct(tpl_new), "Variable"))
      patched <- c(patched, "template")
    }
  }

  message(sprintf("patch_project_data(%s): K-TRACES overrides applied to %s",
                  version, paste(unique(patched), collapse = ", ")))
  invisible(TRUE)
}
