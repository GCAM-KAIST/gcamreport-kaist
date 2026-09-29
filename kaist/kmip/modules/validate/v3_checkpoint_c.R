################################################################################
# v3 / checkpoint C: parent variable = sum of children within one stage file.
# Catches double counting (b5-class bugs). Relations: step5_relations.
################################################################################

checkpoint_c <- function(stage_long, stage_id, relations, known_violations,
                         tol_default) {
  results <- list()
  mm <- list()

  applicable <- relations[vapply(strsplit(relations$stages, ";"),
                                 function(s) stage_id %in% s, logical(1)), ]

  for (i in seq_len(nrow(applicable))) {
    rel_id <- applicable$relation_id[i]
    parent <- applicable$parent[i]
    kids <- trimws(strsplit(applicable$children[i], ";")[[1]])

    p <- stage_long %>% filter(Variable == parent) %>%
      group_by(Scenario, Region, year) %>%
      summarise(parent_val = sum(value), .groups = "drop")
    if (nrow(p) == 0) {
      results[[length(results) + 1]] <- v_result("C", rel_id, stage_id, "SKIP",
        detail = paste("parent absent:", parent))
      next
    }
    present_kids <- intersect(kids, unique(stage_long$Variable))
    missing_kids <- setdiff(kids, present_kids)
    k <- stage_long %>% filter(Variable %in% present_kids) %>%
      group_by(Scenario, Region, year) %>%
      summarise(child_sum = sum(value), .groups = "drop")

    j <- left_join(p, k, by = c("Scenario", "Region", "year")) %>%
      mutate(child_sum = ifelse(is.na(child_sum), 0, child_sum),
             rd = rel_diff(parent_val, child_sum))
    bad <- j %>% filter(rd > tol_default)

    if (nrow(bad) > 0) {
      mm[[length(mm) + 1]] <- v_mismatch("C", rel_id, stage_id,
        bad$Scenario, bad$Region, parent, "", bad$year,
        bad$parent_val, bad$child_sum, tol_default,
        "parent != sum(children)")
    }
    detail <- sprintf("%d cells", nrow(j))
    if (length(missing_kids) > 0) {
      detail <- paste0(detail, "; missing children treated as 0: ",
                       paste(missing_kids, collapse = ", "))
    }
    results[[length(results) + 1]] <- v_result("C", rel_id, stage_id,
      ifelse(nrow(bad) == 0, "PASS", "FAIL"),
      n_checked = nrow(j), n_failed = nrow(bad),
      max_rel_diff = max(j$rd), detail = detail)
  }

  # documented gaps: reported as SKIP so they stay visible, never asserted
  kv <- known_violations[vapply(strsplit(known_violations$stages, ";"),
                                function(s) stage_id %in% s, logical(1)), ]
  for (i in seq_len(nrow(kv))) {
    results[[length(results) + 1]] <- v_result("C", kv$violation_id[i],
      stage_id, "SKIP", detail = paste("known violation:", kv$reason[i]))
  }

  list(results = bind_rows(results),
       mismatches = if (length(mm) > 0) bind_rows(mm) else NULL)
}
