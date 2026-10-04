suppressMessages(devtools::load_all(".", quiet=TRUE)); suppressMessages(library(dplyr))
raw <- readr::read_csv("inst/extdata/mappings/GCAM9.1/en_price_map.csv", comment = "#", na = "",
                       col_types = readr::cols(.default = readr::col_character(), unit_conv = readr::col_double()))
full <- raw %>% gather_map()
# keep shipped behaviour: drop the two delivered-coal rows that the shipped .rda never contained and that
# en_demand_price_map_v9.1 cannot consume (see Error_Log/README.md section 4)
energy_price_map_v9.1 <- full %>% filter(!(market == "delivered coal" & var %in% c("Price|Final Energy|Residential|Space Heating|Solids", "Price|Final Energy|Residential|Space Heating|Solids|Coal")))
usethis::use_data(energy_price_map_v9.1, overwrite = TRUE)
e <- new.env(); load("debug/case1_chemical_feedback_Sector/Error_Log/energy_price_map_v9.1_BEFORE.rda", envir=e); old <- e$energy_price_map_v9.1
rm(energy_price_map_v9.1); load("data/energy_price_map_v9.1.rda"); new <- energy_price_map_v9.1
cat("old:", nrow(old), " new:", nrow(new), "\n")
cat("--- OLD not in NEW ---\n"); print(as.data.frame(anti_join(old, new, by=names(old))))
cat("--- NEW not in OLD ---\n"); print(as.data.frame(anti_join(new, old, by=names(old))))
stopifnot(nrow(anti_join(old, new, by=names(old))) == 0, nrow(anti_join(new, old, by=names(old))) == 5)
cat("ASSERT OK\n")
