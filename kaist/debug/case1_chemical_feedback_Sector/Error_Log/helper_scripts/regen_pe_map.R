suppressMessages(devtools::load_all(".", quiet=TRUE)); suppressMessages(library(dplyr))
raw <- readr::read_csv("inst/extdata/mappings/GCAM9.1/primary_energy_map.csv", comment = "#", na = "",
                       col_types = readr::cols(.default = readr::col_character(), unit_conv = readr::col_double()))
cat("parse problems:", nrow(readr::problems(raw)), "\n")
primary_energy_map_v9.1 <- raw %>% gather_map()
usethis::use_data(primary_energy_map_v9.1, overwrite = TRUE)
e <- new.env(); load("debug/case1_chemical_feedback_Sector/Error_Log/primary_energy_map_v9.1_BEFORE.rda", envir=e); old <- e$primary_energy_map_v9.1
rm(primary_energy_map_v9.1); load("data/primary_energy_map_v9.1.rda"); new <- primary_energy_map_v9.1
cat("old:", nrow(old), " new:", nrow(new), "\n"); str(old)
cat("--- OLD not in NEW ---\n"); print(as.data.frame(anti_join(old, new, by=names(old))))
cat("--- NEW not in OLD ---\n"); print(as.data.frame(anti_join(new, old, by=names(old))))
