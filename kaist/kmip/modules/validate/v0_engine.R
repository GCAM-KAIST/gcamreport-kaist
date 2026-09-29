################################################################################
# v0: shared machinery for step5 validation (functions only, no I/O side
# effects except the report writers). Long format everywhere:
#   (Model, Scenario, Region, Variable, Unit, year<chr>, value<dbl>)
################################################################################

rel_diff <- function(a, b, eps = 1e-12) {
  abs(a - b) / pmax(abs(a), abs(b), eps)
}

# Read a report file (.xlsx or .csv) into the shared long format.
# na_to_zero = FALSE keeps NA (checkpoint D needs missing vs zero).
load_report_long <- function(path, na_to_zero = TRUE) {
  if (grepl("\\.xlsx$", path)) {
    df <- readxl::read_excel(path)
  } else {
    df <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  }
  names(df) <- gsub("^X(\\d{4})$", "\\1", names(df))
  names(df) <- as.character(names(df))
  yc <- names(df)[grepl("^[0-9]{4}$", names(df))]
  df %>%
    select(any_of(c("Model", "Scenario", "Region", "Variable", "Unit")), all_of(yc)) %>%
    mutate(across(all_of(yc), as.numeric)) %>%
    pivot_longer(all_of(yc), names_to = "year", values_to = "value") %>%
    { if (na_to_zero) mutate(., value = ifelse(is.na(value), 0, value)) else . }
}

# One summary record.
v_result <- function(checkpoint, check_id, stage, status,
                     n_checked = 0, n_failed = 0, max_rel_diff = NA_real_,
                     detail = "") {
  tibble::tibble(checkpoint = checkpoint, check_id = check_id, stage = stage,
                 status = status, n_checked = n_checked, n_failed = n_failed,
                 max_rel_diff = max_rel_diff, detail = detail)
}

# One mismatch record (vectorized over its arguments).
v_mismatch <- function(checkpoint, check_id, stage, scenario, region,
                       variable, unit, year, expected, actual, tol, note = "") {
  tibble::tibble(checkpoint = checkpoint, check_id = check_id, stage = stage,
                 scenario = scenario, region = region, variable = variable,
                 unit = unit, year = year, expected = expected, actual = actual,
                 rel_diff = rel_diff(expected, actual), tol = tol, note = note)
}

# Index of the first exception pattern matching each variable (NA = none).
match_exception <- function(vars, patterns) {
  idx <- rep(NA_integer_, length(vars))
  for (i in seq_along(patterns)) {
    hit <- is.na(idx) & grepl(patterns[i], vars)
    idx[hit] <- i
  }
  idx
}

# Compare two pipeline stages. `exceptions` must already be scope-filtered.
# Returns list(results, mismatches).
compare_stage <- function(old_long, new_long, exceptions, tol_rel,
                          checkpoint, check_id, stage_id) {
  results <- list()
  mm <- list()

  common_years <- intersect(unique(old_long$year), unique(new_long$year))
  old_long <- old_long %>% filter(year %in% common_years)
  new_long <- new_long %>% filter(year %in% common_years)

  vars <- union(unique(old_long$Variable), unique(new_long$Variable))
  exc_idx <- match_exception(vars, exceptions$pattern)
  var_type <- tibble::tibble(
    Variable = vars,
    exc_type = ifelse(is.na(exc_idx), "strict", exceptions$type[exc_idx]),
    exc_module = ifelse(is.na(exc_idx), "", exceptions$module[exc_idx])
  )

  key_full <- c("Scenario", "Region", "Variable", "Unit", "year")
  key_nounit <- setdiff(key_full, "Unit")

  # strict + unit_only rows: values must match within tol
  for (grp in list(list(types = "strict", key = key_full),
                   list(types = "unit_only", key = key_nounit))) {
    gvars <- var_type$Variable[var_type$exc_type %in% grp$types]
    o <- old_long %>% filter(Variable %in% gvars) %>%
      group_by(across(all_of(grp$key))) %>%
      summarise(value = sum(value), .groups = "drop")
    n <- new_long %>% filter(Variable %in% gvars) %>%
      group_by(across(all_of(grp$key))) %>%
      summarise(value = sum(value), .groups = "drop")
    j <- full_join(o, n, by = grp$key, suffix = c("_old", "_new"))

    lost <- j %>% filter(is.na(value_new) & value_old != 0)
    extra <- j %>% filter(is.na(value_old) & value_new != 0)
    both <- j %>% filter(!is.na(value_old) & !is.na(value_new)) %>%
      mutate(rd = rel_diff(value_old, value_new)) %>%
      filter(rd > tol_rel)

    label <- if (grp$types == "strict") "pass_through" else "unit_only"
    if (nrow(lost) > 0) {
      mm[[length(mm) + 1]] <- v_mismatch(checkpoint, paste0(check_id, ":lost"),
        stage_id, lost$Scenario, lost$Region, lost$Variable,
        if ("Unit" %in% names(lost)) lost$Unit else "", lost$year,
        lost$value_old, 0, tol_rel, "row lost in new stage")
    }
    if (nrow(extra) > 0) {
      mm[[length(mm) + 1]] <- v_mismatch(checkpoint, paste0(check_id, ":extra"),
        stage_id, extra$Scenario, extra$Region, extra$Variable,
        if ("Unit" %in% names(extra)) extra$Unit else "", extra$year,
        0, extra$value_new, tol_rel, "unexpected new row (no exception matches)")
    }
    if (nrow(both) > 0) {
      mm[[length(mm) + 1]] <- v_mismatch(checkpoint, paste0(check_id, ":value"),
        stage_id, both$Scenario, both$Region, both$Variable,
        if ("Unit" %in% names(both)) both$Unit else "", both$year,
        both$value_old, both$value_new, tol_rel, "value changed outside exceptions")
    }
    n_bad <- nrow(lost) + nrow(extra) + nrow(both)
    results[[length(results) + 1]] <- v_result(checkpoint,
      paste(check_id, label, sep = ":"), stage_id,
      ifelse(n_bad == 0, "PASS", "FAIL"),
      n_checked = nrow(j), n_failed = n_bad,
      max_rel_diff = ifelse(nrow(both) > 0, max(both$rd), 0),
      detail = sprintf("%d lost / %d extra / %d value", nrow(lost), nrow(extra), nrow(both)))
  }

  # exception rows with verify == "exists": module output must be present
  ver <- exceptions %>% filter(verify == "exists")
  for (i in seq_len(nrow(ver))) {
    n_new <- sum(grepl(ver$pattern[i], new_long$Variable))
    results[[length(results) + 1]] <- v_result(checkpoint,
      paste0(check_id, ":exists:", ver$module[i]), stage_id,
      ifelse(n_new > 0, "PASS", "WARN"),
      n_checked = 1, n_failed = as.integer(n_new == 0),
      detail = ifelse(n_new > 0,
                      sprintf("%d rows match %s", n_new, ver$pattern[i]),
                      sprintf("no rows match %s -- module %s may not have run",
                              ver$pattern[i], ver$module[i])))
  }

  list(results = bind_rows(results),
       mismatches = if (length(mm) > 0) bind_rows(mm) else NULL)
}

write_step5_reports <- function(results, mismatches, unmapped, output_dir) {
  write.csv(results, file.path(output_dir, "step5_summary.csv"), row.names = FALSE)
  write.csv(if (is.null(mismatches)) data.frame() else mismatches,
            file.path(output_dir, "step5_mismatches.csv"), row.names = FALSE)
  write.csv(if (is.null(unmapped)) data.frame() else unmapped,
            file.path(output_dir, "step5_unmapped.csv"), row.names = FALSE)
}
