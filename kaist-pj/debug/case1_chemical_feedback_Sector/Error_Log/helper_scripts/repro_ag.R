suppressMessages(devtools::load_all(".", quiet=TRUE))
prj <<- rgcam::loadProject("debug/case1_chemical_feedback_Sector/Input/u0909r_Ref_u0909.dat")
years_in_prj <<- sort(unique(rgcam::getQuery(prj, "regional biomass consumption")$year))
final_year.global <<- 2050
desired_variables.global <<- "All"
desired_regions.global <<- "All"
.myGlobals$ignore.global <- "^bio-ceiling$"
cat("ignore.global =", .myGlobals$ignore.global, "\n")
get_biomass_shares("v9.1")
res <- try(get_ag_demand("v9.1"))
if (inherits(res, "try-error")) {
  cat("FAILED\n"); print(left_join_strict_details)
} else {
  cat("OK rows:", nrow(ag_demand_clean), "\n")
}
