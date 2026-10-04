suppressMessages(library(dplyr))
prj <- rgcam::loadProject("debug/case1_chemical_feedback_Sector/Input/u0909r_Ref_u0909.dat")
for (qn in rgcam::listQueries(prj)) { d <- rgcam::getQuery(prj, qn); if ("fuel" %in% names(d)) { cat("\n==", qn, "== fuels:\n"); print(sort(unique(d$fuel))) } }
