suppressMessages(devtools::load_all(".", reset = TRUE, quiet = TRUE))
GCAM_version <- "v9.1"
stopifnot(GCAM_version %in% gcamreport::available_GCAM_versions)   # <- the line unique to debug.R
cat("after gcamreport:: call: is dev namespace still the one in use? ", identical(asNamespace("gcamreport"), environment(generate_report)), "\n")
cat("dplyr attached:", "package:dplyr" %in% search(), "\n")
prj <<- rgcam::loadProject("debug/case1_chemical_feedback_Sector/Input/u0909r_Ref_u0909.dat")
years_in_prj <<- sort(unique(rgcam::getQuery(prj, "regional biomass consumption")$year))
final_year.global <<- 2050; desired_variables.global <<- "All"; desired_regions.global <<- "All"
.myGlobals$ignore.global <- "^bio-ceiling$"
get_biomass_shares("v9.1")
res <- try(get_ag_demand("v9.1"))
cat(if (inherits(res, "try-error")) "FAILED with gcamreport:: line\n" else paste("OK rows:", nrow(ag_demand_clean), "\n"))
