################################################################################
# v1 / checkpoint A: raw rgcam query sums vs step1 report, plus detection of
# query keys absent from the mapping rdas (silently dropped upstream via
# filter(var != 'NoReported', !is.na(var)) -- the kaist9 migration risk).
# `maps` lets tests inject in-memory mapping overrides.
################################################################################

# Keys in the query but not in the map (unmapped), and map rows the query hits
# that are marked NoReported/NA (mapped but dropped).
detect_unmapped <- function(query_df, map_df, join_keys) {
  missing_cols <- setdiff(join_keys, names(query_df))
  if (length(missing_cols) > 0) {
    return(list(error = paste("key column(s) not in query:",
                              paste(missing_cols, collapse = ", "))))
  }
  qkeys <- query_df %>%
    group_by(across(all_of(join_keys))) %>%
    summarise(n_query_rows = n(), max_abs_value = max(abs(value)), .groups = "drop")
  mkeys <- map_df %>% distinct(across(all_of(join_keys)))

  unmapped <- anti_join(qkeys, mkeys, by = join_keys) %>%
    mutate(status = "unmapped")
  no_rep <- map_df %>%
    filter(is.na(var) | var == "NoReported") %>%
    distinct(across(all_of(join_keys))) %>%
    inner_join(qkeys, by = join_keys) %>%
    mutate(status = "no_reported")
  list(error = NULL, findings = bind_rows(unmapped, no_rep))
}

checkpoint_a <- function(prj, report_long, registry, tol_default,
                         maps = list(), version = version_number,
                         max_year = Inf) {
  results <- list()
  mm <- list()
  unmapped_out <- list()

  available <- rgcam::listQueries(prj)
  report_scens <- unique(report_long$Scenario)
  report_regions <- unique(report_long$Region)

  for (i in seq_len(nrow(registry))) {
    row <- registry[i, ]
    qnames <- trimws(strsplit(row$query_names, ";")[[1]])
    fexprs <- strsplit(row$filter_exprs, ";")[[1]]
    fexprs <- c(fexprs, rep("", length(qnames) - length(fexprs)))

    absent <- setdiff(qnames, available)
    if (length(absent) > 0) {
      results[[length(results) + 1]] <- v_result("A", row$aggregate_id, "raw_vs_step1",
        "SKIP", detail = paste("query not in .dat:", paste(absent, collapse = "; ")))
      next
    }

    # mapping rda (needed for mapped-only sums AND coverage)
    map_df <- NULL
    if (nzchar(row$map_prefix)) {
      map_df <- maps[[row$map_prefix]]
      if (is.null(map_df)) {
        map_df <- tryCatch(load_gcam_rda(row$map_prefix, version), error = function(e) NULL)
      }
      if (is.null(map_df)) {
        results[[length(results) + 1]] <- v_result("A", row$aggregate_id, "raw_vs_step1",
          "SKIP",
          detail = paste0("data/", row$map_prefix, "_v", version, ".rda not found -- ",
                          "run inst/extdata/saveDataFiles_GCAM", version,
                          ".R then patch_gcam_data()"))
        next
      }
    }
    join_keys <- if (nzchar(row$join_keys)) trimws(strsplit(row$join_keys, ";")[[1]]) else character(0)

    # pull + prep + filter each query
    qlist <- list()
    for (k in seq_along(qnames)) {
      q <- rgcam::getQuery(prj, qnames[k]) %>%
        filter(region %in% report_regions)
      if (identical(row$prep, "elec_output")) q <- q %>% mutate(output = "electricity")
      if (nzchar(trimws(fexprs[k]))) {
        q <- q %>% filter(!!rlang::parse_expr(fexprs[k]))
      }
      qlist[[k]] <- q
    }

    tol <- ifelse(is.na(row$tol_rel), tol_default, row$tol_rel)

    # numeric: raw sum vs report-side variable sum. With a mapping, only keys
    # the map reports are summed (mirrors the upstream join + NoReported drop).
    if (row$mode %in% c("full", "total_only") && nzchar(row$report_vars_add)) {
      numeric_qlist <- qlist
      if (!is.null(map_df) && length(join_keys) > 0) {
        reported_keys <- map_df %>%
          filter(!is.na(var), var != "NoReported") %>%
          distinct(across(all_of(join_keys)))
        numeric_qlist <- lapply(qlist, function(q) semi_join(q, reported_keys, by = join_keys))
      }
      raw <- bind_rows(lapply(numeric_qlist, function(q)
        q %>% group_by(scenario, region, year) %>%
          summarise(value = sum(value), .groups = "drop"))) %>%
        group_by(scenario, region, year) %>%
        summarise(raw_val = sum(value) * row$factor, .groups = "drop") %>%
        filter(year <= min(max_year, row$max_year, na.rm = TRUE)) %>%
        mutate(year = as.character(year)) %>%
        filter(scenario %in% report_scens)

      add_vars <- trimws(strsplit(row$report_vars_add, ";")[[1]])
      sub_vars <- if (nzchar(row$report_vars_subtract))
        trimws(strsplit(row$report_vars_subtract, ";")[[1]]) else character(0)
      rep_side <- report_long %>%
        filter(Variable %in% c(add_vars, sub_vars)) %>%
        mutate(sgn = ifelse(Variable %in% sub_vars, -1, 1)) %>%
        group_by(Scenario, Region, year) %>%
        summarise(rep_val = sum(sgn * value), .groups = "drop")

      j <- inner_join(raw, rep_side,
                      by = c("scenario" = "Scenario", "region" = "Region", "year")) %>%
        mutate(rd = rel_diff(raw_val, rep_val))
      bad <- j %>% filter(rd > tol)
      if (nrow(bad) > 0) {
        mm[[length(mm) + 1]] <- v_mismatch("A", row$aggregate_id, "raw_vs_step1",
          bad$scenario, bad$region, row$report_vars_add, "", bad$year,
          bad$raw_val, bad$rep_val, tol, "raw query sum != report value")
      }
      results[[length(results) + 1]] <- v_result("A",
        paste0(row$aggregate_id, ":sum"), "raw_vs_step1",
        ifelse(nrow(j) == 0, "SKIP", ifelse(nrow(bad) == 0, "PASS", "FAIL")),
        n_checked = nrow(j), n_failed = nrow(bad),
        max_rel_diff = ifelse(nrow(j) > 0, max(j$rd), NA),
        detail = ifelse(nrow(j) == 0, "no overlapping scenario/region/year", row$note))
    }

    # coverage: query keys vs mapping rda
    if (row$mode %in% c("full", "coverage_only") && !is.null(map_df)) {
      det <- detect_unmapped(bind_rows(qlist), map_df, join_keys)
      if (!is.null(det$error)) {
        results[[length(results) + 1]] <- v_result("A",
          paste0(row$aggregate_id, ":coverage"), "raw_vs_step1", "WARN",
          detail = det$error)
        next
      }
      f <- det$findings
      n_unmapped <- sum(f$status == "unmapped")
      n_norep <- sum(f$status == "no_reported")
      if (nrow(f) > 0) {
        keys <- f %>% select(all_of(join_keys))
        unmapped_out[[length(unmapped_out) + 1]] <- tibble::tibble(
          aggregate_id = row$aggregate_id,
          query_name = row$query_names,
          mapping_object = paste0(row$map_prefix, "_v", version),
          status = f$status,
          key_names = paste(join_keys, collapse = ";"),
          key1 = as.character(keys[[1]]),
          key2 = if (length(join_keys) >= 2) as.character(keys[[2]]) else "",
          key3 = if (length(join_keys) >= 3) as.character(keys[[3]]) else "",
          n_query_rows = f$n_query_rows,
          max_abs_value = f$max_abs_value)
      }
      results[[length(results) + 1]] <- v_result("A",
        paste0(row$aggregate_id, ":coverage"), "raw_vs_step1",
        ifelse(n_unmapped > 0, "FAIL", ifelse(n_norep > 0, "WARN", "PASS")),
        n_checked = nrow(bind_rows(qlist) %>% distinct(across(all_of(join_keys)))),
        n_failed = n_unmapped,
        detail = sprintf("%d unmapped, %d NoReported keys", n_unmapped, n_norep))
    }
  }

  list(results = bind_rows(results),
       mismatches = if (length(mm) > 0) bind_rows(mm) else NULL,
       unmapped = if (length(unmapped_out) > 0) bind_rows(unmapped_out) else NULL)
}
