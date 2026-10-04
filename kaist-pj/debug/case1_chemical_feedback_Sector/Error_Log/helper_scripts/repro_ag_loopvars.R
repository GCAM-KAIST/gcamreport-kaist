suppressMessages(devtools::load_all(".", reset = TRUE, quiet = TRUE))
GCAM_version <- "v9.1"
stopifnot(GCAM_version %in% gcamreport::available_GCAM_versions)
db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
report_dir <- file.path(db_path, "reports_u0909")
jobs <- data.frame(db = c("u0909r", "u0909n"), scenario = c("KAIST_9_ref_u0909", "KAIST_9_NZ_u0909"), label = c("Ref_u0909", "NZ_u0909"))
i <- 1L; job <- jobs[i, ]
cat("internal variable names that also exist as globals now:\n")
nm <- var_fun_map_v9.1$name; print(nm[sapply(nm, function(x) exists(x, envir = globalenv()))])
prj <<- rgcam::loadProject(file.path(db_path, "u0909r_Ref_u0909.dat"))
years_in_prj <<- sort(unique(rgcam::getQuery(prj, "regional biomass consumption")$year))
final_year.global <<- 2050; desired_variables.global <<- "All"; desired_regions.global <<- "All"
.myGlobals$ignore.global <- "^bio-ceiling$"
get_biomass_shares("v9.1")
res <- try(get_ag_demand("v9.1"))
cat(if (inherits(res, "try-error")) "FAILED with loop globals\n" else paste("OK rows:", nrow(ag_demand_clean), "\n"))
