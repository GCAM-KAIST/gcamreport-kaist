suppressMessages(devtools::load_all(".", quiet=TRUE)); suppressMessages(library(dplyr))
ct <- readr::cols(.default = readr::col_character(), unit_conv = readr::col_double())
full <- readr::read_csv("inst/extdata/mappings/GCAM9.1/en_price_map.csv", comment = "#", na = "", col_types = ct) %>% gather_map()
energy_price_map_v9.1 <- full %>% filter(!(market == "delivered coal" & var %in% c("Price|Final Energy|Residential|Space Heating|Solids", "Price|Final Energy|Residential|Space Heating|Solids|Coal")))
usethis::use_data(energy_price_map_v9.1, overwrite = TRUE)
primary_energy_map_v9.1 <- readr::read_csv("inst/extdata/mappings/GCAM9.1/primary_energy_map.csv", comment = "#", na = "", col_types = ct) %>% gather_map()
usethis::use_data(primary_energy_map_v9.1, overwrite = TRUE)
chk <- function(name) {
  e <- new.env(); load(sprintf("debug/case1_chemical_feedback_Sector/Error_Log/%s_BEFORE.rda", name), envir=e); old <- e[[name]]
  e2 <- new.env(); load(sprintf("data/%s.rda", name), envir=e2); new <- e2[[name]]
  cat("\n", name, ": old", nrow(old), "new", nrow(new), "old-not-new", nrow(anti_join(old, new, by=names(old))), "\n")
  print(as.data.frame(anti_join(new, old, by=names(old))))
  stopifnot(nrow(anti_join(old, new, by=names(old))) == 0)
}
chk("energy_price_map_v9.1"); chk("primary_energy_map_v9.1"); cat("ASSERT OK\n")
