suppressMessages(devtools::load_all(".", quiet=TRUE)); suppressMessages(library(dplyr))
raw <- readr::read_csv("inst/extdata/mappings/GCAM9.1/ag_demand_map.csv", comment = "#", na = "", col_types = readr::cols(.default = readr::col_character(), unit_conv = readr::col_double()))
ag_demand_map_v9.1 <- raw %>% gather_map(); usethis::use_data(ag_demand_map_v9.1, overwrite = TRUE)
e <- new.env(); load("debug/case1_chemical_feedback_Sector/Error_Log/ag_demand_map_v9.1_BEFORE.rda", envir=e); old <- e$ag_demand_map_v9.1
e2 <- new.env(); load("data/ag_demand_map_v9.1.rda", envir=e2); new <- e2$ag_demand_map_v9.1
cat("old:", nrow(old), "new:", nrow(new), "old-not-new:", nrow(anti_join(old, new, by=names(old))), "\n"); str(old)
print(as.data.frame(anti_join(new, old, by=names(old)))); stopifnot(nrow(anti_join(old, new, by=names(old))) == 0, nrow(anti_join(new, old, by=names(old))) == 1); cat("ASSERT OK\n")
