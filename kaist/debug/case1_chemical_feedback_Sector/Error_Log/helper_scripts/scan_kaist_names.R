suppressMessages(library(dplyr))
prj <- rgcam::loadProject("debug/case1_chemical_feedback_Sector/Input/u0909r_Ref_u0909.dat")
pat <- "ceiling|uranium|imported H2|chemical feedstocks"
for (qn in rgcam::listQueries(prj)) {
  d <- rgcam::getQuery(prj, qn)
  for (cn in setdiff(names(d), c("Units","scenario","year","value"))) {
    if (is.character(d[[cn]])) {
      v <- unique(d[[cn]][grepl(pat, d[[cn]])])
      v <- v[!grepl("^globalbio-ceiling$", v)]
      if (length(v) > 0) {
        if (cn == "sector" && any(v == "chemical feedstocks") && "technology" %in% names(d)) {
          v2 <- unique(paste(d$sector, d$subsector, d$technology)[d$sector == "chemical feedstocks"])
          cat(sprintf("%-60s | %-10s | %s\n", qn, "sector/tech", paste(v2, collapse="; ")))
        } else cat(sprintf("%-60s | %-10s | %s\n", qn, cn, paste(head(v, 8), collapse="; ")))
      }
    }
  }
}
