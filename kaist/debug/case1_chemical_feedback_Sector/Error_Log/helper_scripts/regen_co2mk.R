suppressMessages(devtools::load_all(".", quiet=TRUE)); suppressMessages(library(dplyr))
co2_market_v9.1 <- readr::read_csv("inst/extdata/mappings/GCAM9.1/CO2market_new.csv", comment = "#", col_types = readr::cols(.default = readr::col_character()))
usethis::use_data(co2_market_v9.1, overwrite = TRUE)
e <- new.env(); load("debug/case1_chemical_feedback_Sector/Error_Log/co2_market_v9.1_BEFORE.rda", envir=e); old <- e$co2_market_v9.1
e2 <- new.env(); load("data/co2_market_v9.1.rda", envir=e2); new <- e2$co2_market_v9.1
cat("old:", nrow(old), "new:", nrow(new), "old-not-new:", nrow(anti_join(old, new, by=names(old))), "\n"); str(old); str(new)
d <- anti_join(new, old, by=names(old)); cat("new rows:", nrow(d), " markets:", paste(unique(d$market), collapse=","), " includes South Korea:", "South Korea" %in% d$region, "\n")
stopifnot(nrow(anti_join(old, new, by=names(old))) == 0, nrow(d) == 31, all(d$market == "rowCO2")); cat("ASSERT OK\n")
