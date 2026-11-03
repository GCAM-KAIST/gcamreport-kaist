################################################################################
# b10: hydrogen rows read from GCAM inputs (Korea only)
#
# Creates from the "inputs by tech" query (EJ/yr):
#   - Secondary Energy|Hydrogen|Import: the KAIST "imported H2" market consumed
#     by the H2 pipeline and H2 liquid truck sectors (subsector "imported H2").
#     The supply side of the same flow (the "imported H2" sector's input of the
#     exporters' H2 central production) is not counted.
#   - Primary Energy|Electricity|Hydrogen: grid electricity into electrolysis,
#     central (elect_td_ind) and onsite in H2 industrial, H2 LDV, H2 MHDV, LH2
#     (elect_td_ind, elect_td_trn). Nuclear and hybrid electrolysis use
#     resources, not electricity, and the gas technologies' auxiliary power is
#     not electrolysis, so the filter is on technology "electrolysis". Replaces
#     the b2 coefficient method, which multiplied all electrolysis output
#     (nuclear and hybrid included, onsite left out) by the grid coefficient.
# Must run after b2.
################################################################################

add_hydrogen_rows <- function(data, prj, target_rgn = target_region) {
  cat("\n=== Hydrogen rows from inputs by tech ===\n")

  inp <- tryCatch(getQuery(prj, "inputs by tech"), error = function(e) NULL)
  if (is.null(inp) || nrow(inp) == 0) {
    cat("Skipped hydrogen rows (inputs by tech not in project)\n")
    return(data)
  }
  inp <- inp %>% filter(region == target_rgn, scenario %in% unique(data$Scenario))

  long <- bind_rows(
    inp %>%
      filter(input == "imported H2") %>%
      mutate(Variable = "Secondary Energy|Hydrogen|Import"),
    inp %>%
      filter(technology == "electrolysis", input %in% c("elect_td_ind", "elect_td_trn")) %>%
      mutate(Variable = "Primary Energy|Electricity|Hydrogen")
  )
  targets <- tibble::tibble(Variable = c("Secondary Energy|Hydrogen|Import",
                                         "Primary Energy|Electricity|Hydrogen"),
                            Unit = "EJ/yr")
  new_rows <- long_to_rows(long, data, targets)

  cat(sprintf("Added %d hydrogen rows (%s)\n", nrow(new_rows),
              paste(targets$Variable, collapse = ", ")))
  bind_rows(data %>% filter(!Variable %in% targets$Variable), new_rows)
}
