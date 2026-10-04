suppressMessages(library(dplyr))
sp <- "C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad/verify"
a <- readr::read_csv(file.path(sp, "NZ_verify.csv"), show_col_types = FALSE)
b <- readr::read_csv("debug/case1_chemical_feedback_Sector/Input/reports_u0909/NZ_u0909.csv", show_col_types = FALSE)
keys <- c("Model","Scenario","Region","Variable","Unit"); yrs <- setdiff(names(a), keys)
j <- inner_join(a, b, by = keys, suffix = c(".verify",".final"))
rowmax <- apply(sapply(yrs, function(y) { d <- abs(j[[paste0(y,".verify")]] - j[[paste0(y,".final")]]); d[is.na(d)] <- 0; d }), 1, max)
d <- j[rowmax > 1e-9, ]
print(as.data.frame(d %>% count(Variable)))
print(as.data.frame(d %>% filter(Region %in% c("South Korea","USA","World")) %>% select(Region, Variable, `2030.verify`, `2030.final`, `2050.verify`, `2050.final`)))
cat("Price|Carbon nonzero regions in FINAL:", sum((b %>% filter(Variable=="Price|Carbon"))$`2050` != 0), "\n")
