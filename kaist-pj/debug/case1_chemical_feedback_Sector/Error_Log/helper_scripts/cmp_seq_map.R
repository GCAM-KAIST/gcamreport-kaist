suppressMessages(library(dplyr))
e <- new.env(); load("debug/case1_chemical_feedback_Sector/Error_Log/carbon_seq_tech_map_v9.1_BEFORE.rda", envir=e); old <- e$carbon_seq_tech_map_v9.1
load("data/carbon_seq_tech_map_v9.1.rda"); new <- carbon_seq_tech_map_v9.1
cat("old:", nrow(old), " new:", nrow(new), "\n"); str(old); str(new)
cat("--- rows in OLD not in NEW ---\n"); print(as.data.frame(anti_join(old, new, by=names(old))))
cat("--- rows in NEW not in OLD ---\n"); print(as.data.frame(anti_join(new, old, by=names(old))))
