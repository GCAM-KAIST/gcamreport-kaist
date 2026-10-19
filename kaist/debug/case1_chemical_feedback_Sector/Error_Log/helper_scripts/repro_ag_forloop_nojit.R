compiler::enableJIT(0)
suppressMessages(devtools::load_all(".", reset = TRUE, quiet = TRUE))
cat("JIT level:", compiler::enableJIT(-1), "\n")
db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
prj <<- rgcam::loadProject(file.path(db_path, "u0909r_Ref_u0909.dat"))
years_in_prj <<- sort(unique(rgcam::getQuery(prj, "regional biomass consumption")$year))
final_year.global <<- 2050; desired_variables.global <<- "All"; desired_regions.global <<- "All"
.myGlobals$ignore.global <- "^bio-ceiling$"
get_biomass_shares("v9.1")
for (k in 1) {
  res <- try(get_ag_demand("v9.1"))
  cat(if (inherits(res, "try-error")) "FAILED inside for loop\n" else paste("OK inside for loop, rows:", nrow(ag_demand_clean), "\n"))
}
