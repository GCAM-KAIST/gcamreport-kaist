################################################################################
# v2 / checkpoint B: step1 vs step2 -- totals unchanged except the documented
# module adjustments (step5_exceptions), plus identity checks for added rows.
################################################################################

# B1: step1 xlsx vs step2 all-regions csv (Part A exceptions, scope "all")
checkpoint_b1 <- function(step1_long, step2_long, exceptions, tol) {
  compare_stage(step1_long, step2_long,
                exceptions %>% filter(scope == "all"),
                tol, "B", "B1", "step1_vs_step2all")
}

# B2: step2 csv (Korea subset) vs korea csv (Part B exceptions, scope "korea")
checkpoint_b2 <- function(pre_long, korea_long, exceptions, tol) {
  compare_stage(pre_long, korea_long,
                exceptions %>% filter(scope == "korea"),
                tol, "B", "B2", "step2all_vs_korea")
}

# b3 identity: Coal|Fuel + Coal|Feedstock == untouched Solids|Coal source row
identity_b3 <- function(korea_long, tol) {
  src <- "Final Energy|Industry|Iron and Steel|Solids|Coal"
  parts <- c("Final Energy|Industry|Iron and Steel|Coal|Fuel",
             "Final Energy|Industry|Iron and Steel|Coal|Feedstock")
  s <- korea_long %>% filter(Variable == src) %>%
    group_by(Scenario, year) %>% summarise(src_val = sum(value), .groups = "drop")
  p <- korea_long %>% filter(Variable %in% parts) %>%
    group_by(Scenario, year) %>% summarise(part_sum = sum(value), .groups = "drop")
  if (nrow(s) == 0 || nrow(p) == 0) {
    return(list(results = v_result("B", "identity_b3", "korea", "SKIP",
                                   detail = "b3 variables not present"),
                mismatches = NULL))
  }
  j <- inner_join(s, p, by = c("Scenario", "year")) %>%
    mutate(rd = rel_diff(src_val, part_sum))
  bad <- j %>% filter(rd > tol)
  mm <- NULL
  if (nrow(bad) > 0) {
    mm <- v_mismatch("B", "identity_b3", "korea", bad$Scenario, "",
                     src, "", bad$year, bad$src_val, bad$part_sum, tol,
                     "Coal Fuel+Feedstock != Solids|Coal")
  }
  list(results = v_result("B", "identity_b3", "korea",
                          ifelse(nrow(bad) == 0, "PASS", "FAIL"),
                          n_checked = nrow(j), n_failed = nrow(bad),
                          max_rel_diff = max(j$rd)),
       mismatches = mm)
}

# b5 identity: korea[sources] + korea[Biomass|Liquids] == pre-PartB[sources]
identity_b5 <- function(pre_long, korea_long, pairs, tol) {
  results <- list()
  mm <- list()
  for (i in seq_len(nrow(pairs))) {
    bioliq <- pairs$bioliq_variable[i]
    srcs <- trimws(strsplit(pairs$source_variables[i], ";")[[1]])

    pre_sum <- pre_long %>% filter(Variable %in% srcs) %>%
      group_by(Scenario, year) %>% summarise(pre_val = sum(value), .groups = "drop")
    new_sum <- korea_long %>% filter(Variable %in% srcs) %>%
      group_by(Scenario, year) %>% summarise(new_val = sum(value), .groups = "drop")
    bio <- korea_long %>% filter(Variable == bioliq) %>%
      group_by(Scenario, year) %>% summarise(bio_val = sum(value), .groups = "drop")
    if (nrow(pre_sum) == 0 || nrow(bio) == 0) {
      results[[length(results) + 1]] <- v_result("B",
        paste0("identity_b5:", bioliq), "korea", "SKIP",
        detail = "source or Biomass|Liquids row absent")
      next
    }
    j <- pre_sum %>%
      inner_join(new_sum, by = c("Scenario", "year")) %>%
      inner_join(bio, by = c("Scenario", "year")) %>%
      mutate(rd = rel_diff(pre_val, new_val + bio_val))
    bad <- j %>% filter(rd > tol)
    if (nrow(bad) > 0) {
      mm[[length(mm) + 1]] <- v_mismatch("B", "identity_b5", "korea",
        bad$Scenario, "", bioliq, "", bad$year,
        bad$pre_val, bad$new_val + bad$bio_val, tol,
        "Liquids_new + Biomass|Liquids != Liquids_pre (b5 conservation)")
    }
    results[[length(results) + 1]] <- v_result("B",
      paste0("identity_b5:", bioliq), "korea",
      ifelse(nrow(bad) == 0, "PASS", "FAIL"),
      n_checked = nrow(j), n_failed = nrow(bad), max_rel_diff = max(j$rd))
  }
  list(results = bind_rows(results),
       mismatches = if (length(mm) > 0) bind_rows(mm) else NULL)
}

# b6 identity: korea[steel energy CO2] + korea[steel process] == pre-PartB[steel CO2]
identity_b6 <- function(pre_long, korea_long, tol) {
  co2_var  <- "Emissions|CO2|Energy|Demand|Industry|Iron and Steel"
  proc_var <- "Emissions|GHGs|Non-Energy|Industrial Process|Iron and Steel"
  pre <- pre_long %>% filter(Variable == co2_var) %>%
    group_by(Scenario, year) %>% summarise(pre_val = sum(value), .groups = "drop")
  energy <- korea_long %>% filter(Variable == co2_var) %>%
    group_by(Scenario, year) %>% summarise(energy_val = sum(value), .groups = "drop")
  process <- korea_long %>% filter(Variable == proc_var) %>%
    group_by(Scenario, year) %>% summarise(proc_val = sum(value), .groups = "drop")
  if (nrow(pre) == 0 || nrow(process) == 0) {
    return(list(results = v_result("B", "identity_b6", "korea", "SKIP",
                                   detail = "b6 variables not present"),
                mismatches = NULL))
  }
  j <- pre %>%
    inner_join(energy, by = c("Scenario", "year")) %>%
    inner_join(process, by = c("Scenario", "year")) %>%
    mutate(rd = rel_diff(pre_val, energy_val + proc_val))
  bad <- j %>% filter(rd > tol)
  mm <- NULL
  if (nrow(bad) > 0) {
    mm <- v_mismatch("B", "identity_b6", "korea", bad$Scenario, "",
                     co2_var, "", bad$year, bad$pre_val, bad$energy_val + bad$proc_val, tol,
                     "steel energy CO2 + process != pre-split steel CO2")
  }
  list(results = v_result("B", "identity_b6", "korea",
                          ifelse(nrow(bad) == 0, "PASS", "FAIL"),
                          n_checked = nrow(j), n_failed = nrow(bad),
                          max_rel_diff = max(j$rd)),
       mismatches = mm)
}
