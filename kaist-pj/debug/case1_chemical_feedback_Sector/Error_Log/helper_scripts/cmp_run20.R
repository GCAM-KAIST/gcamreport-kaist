suppressMessages(library(dplyr))
sp <- "C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad"
rep <- "debug/case1_chemical_feedback_Sector/Input/reports_u0909"
keys <- c("Model","Scenario","Region","Variable","Unit")
refs <- list(Ref = file.path(sp, "verify/Ref_verify.csv"), NZ = file.path(sp, "verify2/NZ_noignore_fix8.csv"))
for (lab in names(refs)) {
  a <- readr::read_csv(refs[[lab]], show_col_types = FALSE); b <- readr::read_csv(file.path(rep, paste0(lab, "_u0909.csv")), show_col_types = FALSE)
  yrs <- setdiff(names(a), keys); j <- inner_join(a, b, by = keys, suffix = c(".a",".b"))
  rowmax <- apply(sapply(yrs, function(y) { d <- abs(j[[paste0(y,".a")]] - j[[paste0(y,".b")]]); d[is.na(d)] <- 0; d }), 1, max)
  cat(sprintf("%s final: rows %d | vs reference rows %d | only-one-side %d/%d | differing %d | max abs diff %.3g | variables %d | regions %d\n",
      lab, nrow(b), nrow(a), nrow(anti_join(a,b,by=keys)), nrow(anti_join(b,a,by=keys)), sum(rowmax>1e-9), max(rowmax), n_distinct(b$Variable), n_distinct(b$Region)))
}
nz <- readr::read_csv(file.path(rep, "NZ_u0909.csv"), show_col_types = FALSE)
pc <- nz %>% filter(Variable == "Price|Carbon"); cat("NZ final Price|Carbon nonzero regions:", sum(pc$`2050` != 0), "of", nrow(pc), "\n")
