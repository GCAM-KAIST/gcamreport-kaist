################################################################################
# v4 / checkpoint D: independently recompute the filled KMIP template from the
# korea csv + mapping + shared unit table, then compare with step4's output
# (variables_after_unit_conversion.csv). Independent reimplementation of the
# step4 arithmetic on purpose -- catches algorithm drift and stale outputs.
################################################################################

# Expected values per mapping row x scenario. Returns long tibble:
# (Scenario, Variable, year, expected, status)
recompute_template <- function(korea_long, mapping, template_units, unit_table,
                               years) {
  mapping_valid <- mapping %>%
    filter(!is.na(gcam_variable) & gcam_variable != "")
  scenarios <- unique(korea_long$Scenario)

  # value/unit lookup: one row per (Scenario, Variable, year)
  lookup <- korea_long %>%
    group_by(Scenario, Variable, year) %>%
    summarise(value = sum(value), Unit = first(Unit),
              n = n(), .groups = "drop")

  get_var <- function(v, scen) lookup %>% filter(Variable == v, Scenario == scen)

  out <- list()
  for (i in seq_len(nrow(mapping_valid))) {
    tv <- mapping_valid$template_variable[i]
    base_var <- mapping_valid$gcam_variable[i]
    adds <- mapping_valid$gcam_variable_add[i]
    subs <- mapping_valid$gcam_variable_subtract[i]

    for (scen in scenarios) {
      base <- get_var(base_var, scen)
      status <- "ok"
      if (nrow(base) == 0) status <- "no_base"
      if (any(base$n > 1)) status <- "ambiguous_base"

      if (status != "ok") {
        out[[length(out) + 1]] <- tibble::tibble(
          Scenario = scen, Variable = tv, year = years,
          expected = NA_real_, status = status)
        next
      }
      base_unit <- base$Unit[1]
      vals <- setNames(rep(0, length(years)), years)
      bv <- setNames(base$value, base$year)
      vals[intersect(years, names(bv))] <- bv[intersect(years, names(bv))]

      for (spec in list(list(txt = adds, sign = 1), list(txt = subs, sign = -1))) {
        if (is.na(spec$txt) || spec$txt == "") next
        for (term in trimws(strsplit(spec$txt, ";")[[1]])) {
          td <- get_var(term, scen)
          if (nrow(td) == 0) next                      # step4: missing -> 0
          if (td$Unit[1] != base_unit) next            # step4: mismatch -> skip term
          tv_vals <- setNames(td$value, td$year)
          yy <- intersect(years, names(tv_vals))
          vals[yy] <- vals[yy] + spec$sign * tv_vals[yy]
        }
      }

      # unit conversion (same rule as step4: no factor found -> 1)
      target <- template_units$target_unit[template_units$Variable == tv][1]
      factor <- 1
      if (!is.na(target) && !is.na(base_unit) && base_unit != target) {
        cr <- unit_table %>% filter(from == base_unit, to == target)
        if (nrow(cr) > 0) factor <- cr$factor[1] else status <- "unit_unconverted"
      }
      out[[length(out) + 1]] <- tibble::tibble(
        Scenario = scen, Variable = tv, year = years,
        expected = as.numeric(vals[years]) * factor, status = status)
    }
  }
  bind_rows(out)
}

checkpoint_d <- function(korea_long, mapping, template_units, unit_table,
                         after_long, tol) {
  years <- sort(intersect(unique(korea_long$year), unique(after_long$year)))
  expected <- recompute_template(korea_long, mapping, template_units,
                                 unit_table, years)

  j <- after_long %>%
    filter(year %in% years) %>%
    select(Scenario, Variable, year, actual = value) %>%
    left_join(expected, by = c("Scenario", "Variable", "year")) %>%
    mutate(
      category = case_when(
        is.na(status) & is.na(actual)  ~ "expected_missing",   # unmapped template row
        is.na(status) & !is.na(actual) ~ "unexpected_value",   # value without mapping
        status %in% c("no_base", "ambiguous_base") & is.na(actual) ~ "lost_row",
        status == "unit_unconverted"   ~ "unit_unconverted",
        !is.na(expected) & is.na(actual) ~ "unexpected_missing",
        rel_diff(expected, actual) <= tol ~ "ok",
        TRUE ~ "value_mismatch"
      )
    )

  bad <- j %>% filter(category %in% c("value_mismatch", "unexpected_missing",
                                      "unexpected_value"))
  mm <- NULL
  if (nrow(bad) > 0) {
    mm <- v_mismatch("D", "template_fill", "step4", bad$Scenario, "",
                     bad$Variable, "", bad$year,
                     ifelse(is.na(bad$expected), 0, bad$expected),
                     ifelse(is.na(bad$actual), 0, bad$actual),
                     tol, bad$category)
  }
  counts <- j %>% count(category)
  n_warn <- sum(j$category %in% c("lost_row", "unit_unconverted"))
  status <- if (nrow(bad) > 0) "FAIL" else if (n_warn > 0) "WARN" else "PASS"

  ok_rows <- j %>% filter(category == "ok")
  list(results = v_result("D", "template_fill", "step4", status,
         n_checked = nrow(j), n_failed = nrow(bad),
         max_rel_diff = ifelse(nrow(ok_rows) > 0,
                               max(rel_diff(ok_rows$expected, ok_rows$actual)), NA),
         detail = paste(sprintf("%s=%d", counts$category, counts$n), collapse = ", ")),
       mismatches = mm)
}
