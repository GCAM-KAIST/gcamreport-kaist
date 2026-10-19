suppressMessages(library(dplyr))
sp <- "C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad"
a <- readr::read_csv(file.path(sp, "verify/NZ_verify.csv"), show_col_types = FALSE)          # run 6: ignore given, fixes 1-6
b <- readr::read_csv(file.path(sp, "verify2/NZ_noignore_fix8.csv"), show_col_types = FALSE)  # run 19: no ignore, fixes 1-8
keys <- c("Model","Scenario","Region","Variable","Unit"); yrs <- setdiff(names(a), keys)
j <- inner_join(a, b, by = keys, suffix = c(".a",".b"))
rowmax <- apply(sapply(yrs, function(y) { d <- abs(j[[paste0(y,".a")]] - j[[paste0(y,".b")]]); d[is.na(d)] <- 0; d }), 1, max)
cat(sprintf("run6 rows %d | run19 rows %d | only-in-6 %d | only-in-19 %d | differing %d | max abs diff %.3g\n", nrow(a), nrow(b), nrow(anti_join(a,b,by=keys)), nrow(anti_join(b,a,by=keys)), sum(rowmax>1e-9), max(rowmax)))
pc <- b %>% filter(Variable=="Price|Carbon"); cat("run19 Price|Carbon nonzero regions:", sum(pc$`2050`!=0), "of", nrow(pc), "; South Korea 2050:", pc$`2050`[pc$Region=="South Korea"], "\n")
