suppressMessages(library(dplyr))
sp <- "C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad/verify"
rep <- "debug/case1_chemical_feedback_Sector/Input/reports_u0909"
keys <- c("Model","Scenario","Region","Variable","Unit")
for (lab in c("Ref","NZ")) {
  a <- readr::read_csv(file.path(sp, paste0(lab, "_verify.csv")), show_col_types = FALSE)
  b <- readr::read_csv(file.path(rep, paste0(lab, "_u0909.csv")), show_col_types = FALSE)
  yrs <- setdiff(names(a), keys)
  j <- inner_join(a, b, by = keys, suffix = c(".a",".b"))
  rowmax <- apply(sapply(yrs, function(y) { d <- abs(j[[paste0(y,".a")]] - j[[paste0(y,".b")]]); d[is.na(d)] <- 0; d }), 1, max)
  cat(sprintf("%s: verify rows %d | final rows %d | only-in-verify %d | only-in-final %d | matched %d | rows differing %d | max abs diff %.3g\n",
      lab, nrow(a), nrow(b), nrow(anti_join(a,b,by=keys)), nrow(anti_join(b,a,by=keys)), nrow(j), sum(rowmax > 1e-9), max(rowmax)))
  cat("   variables:", n_distinct(b$Variable), " regions:", n_distinct(b$Region), " scenario:", unique(b$Scenario), "\n")
}
