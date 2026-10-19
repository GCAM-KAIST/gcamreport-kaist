# In-memory additions to gcamreport v9.1 mapping objects (namespace only;
# mirrors kaist_overrides[["v7.0"]] in kaist/core/functions.R).
ns <- asNamespace("gcamreport")
.add_rows <- function(short, new) {
  nm <- paste0(short, "_v9.1")
  df <- get(nm, envir = ns)
  for (cn in intersect(names(df), names(new))) {
    if (is.numeric(df[[cn]])) new[[cn]] <- as.numeric(new[[cn]]) else new[[cn]] <- as.character(new[[cn]])
  }
  key <- setdiff(intersect(names(df), names(new)), "unit_conv")
  df <- dplyr::anti_join(df, dplyr::distinct(new[key]), by = key)
  df <- dplyr::bind_rows(df, new)
  e <- ns
  while (!exists(nm, envir = e, inherits = FALSE)) e <- parent.env(e)
  if (bindingIsLocked(nm, e)) unlockBinding(nm, e)
  assign(nm, df, envir = e)
  cat("kaist9_runtime_patch:", nm, "+", nrow(new), "rows\n")
}
.add_rows("carbon_seq_tech_map", tibble::tibble(sector = "chemical feedstocks",
          technology = c("coal", "gas"), unit_conv = "1", var = "NoReported"))
.add_rows("energy_price_map", tibble::tibble(market = "imported H2", unit_conv = 1, var = "NoReported"))
.add_rows("primary_energy_map", tibble::tibble(fuel = c("uranium"), unit_conv = 1, var = "NoReported"))
