# DIAGNOSTIC: Ref scenario on the CREATE path (like debug.R) with left_join_strict replaced by the ORIGINAL
# code plus diagnostics printed when unmatched rows remain. Purpose: explain why `ignore` is not honoured
# on the create path (run 1 / run 8) but is on the load path (runs 2,3,7) and with the logging join (run 5).
setwd("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp")
devtools::load_all(".", reset = TRUE)
suppressMessages(library(dplyr))
left_join_strict_diag <- function(left_df, right_df, by = NULL, by_message = by, mapping = "",
                                  ignore = if (exists("ignore.global", envir = .myGlobals)) .myGlobals$ignore.global else NULL, ...) {
  result <- dplyr::left_join(left_df, right_df, by = by, ...)
  unmatched <- result %>% dplyr::filter(dplyr::if_any(-one_of(names(left_df)), is.na))
  if (!is.null(ignore) & nrow(unmatched) > 0) {
    unmatched_ignore <- unmatched %>% dplyr::filter(dplyr::if_any(.cols = everything(), ~ grepl(paste(ignore, collapse = "|"), .)))
    unmatched <- suppressMessages(unmatched %>% dplyr::anti_join(unmatched_ignore))
    result <- suppressMessages(result %>% dplyr::anti_join(unmatched_ignore))
  }
  if (nrow(unmatched) > 0) {
    cat("\n=== DIAG: unmatched rows remain for mapping", mapping, "===\n")
    cat("ignore arg:", deparse(ignore), " | .myGlobals$ignore.global:", deparse(.myGlobals$ignore.global),
        " | exists:", exists("ignore.global", envir = .myGlobals), "\n")
    cat("class(left_df):", paste(class(left_df), collapse=","), " class(result):", paste(class(result), collapse=","), "\n")
    cat("--- str(unmatched) ---\n"); str(unmatched)
    cat("--- head(unmatched) ---\n"); print(head(as.data.frame(unmatched), 3))
    if (!is.null(ignore)) {
      pat <- paste(ignore, collapse = "|")
      cat("--- per-column grepl hits on unmatched ---\n")
      for (cn in names(unmatched)) cat(sprintf("  %-12s class=%-10s hits=%d\n", cn, class(unmatched[[cn]])[1], sum(grepl(pat, unmatched[[cn]]), na.rm = TRUE)))
      ui2 <- unmatched %>% dplyr::filter(dplyr::if_any(.cols = dplyr::everything(), ~ grepl(pat, .)))
      cat("rows matched by if_any(dplyr::everything()):", nrow(ui2), "\n")
      ui3 <- unmatched %>% dplyr::filter(dplyr::if_any(.cols = everything(), ~ grepl(pat, .)))
      cat("rows matched by if_any(everything()):", nrow(ui3), "\n")
      ui4 <- unmatched[apply(unmatched, 1, function(r) any(grepl(pat, r))), ]
      cat("rows matched by base apply/grepl:", nrow(ui4), "\n")
      cat("what does `everything` resolve to here? "); print(environmentName(environment(everything)))
      cat("exists('everything') in globalenv:", exists("everything", envir = globalenv(), inherits = FALSE), "\n")
    }
    cat("=== END DIAG ===\n")
    saveRDS(list(left_df = left_df, unmatched = unmatched, ignore = ignore), "debug/case1_chemical_feedback_Sector/Error_Log/run9_diag_state.rds")
    stop("DIAG STOP: unmatched rows remain for mapping ", mapping)
  }
  result
}
environment(left_join_strict_diag) <- asNamespace("gcamreport")
ns <- asNamespace("gcamreport"); unlockBinding("left_join_strict", ns); assign("left_join_strict", left_join_strict_diag, envir = ns); lockBinding("left_join_strict", ns)
pe <- as.environment("package:gcamreport"); if (exists("left_join_strict", envir = pe, inherits = FALSE)) { unlockBinding("left_join_strict", pe); assign("left_join_strict", left_join_strict_diag, envir = pe) }
GCAM_version <- "v9.1"
db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
scratch <- "C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad/diag"; dir.create(scratch, showWarnings = FALSE, recursive = TRUE)
generate_report(db_path = db_path, db_name = "u0909r", prj_name = "Ref_diag.dat", scenarios = "KAIST_9_ref_u0909",
  GCAM_version = GCAM_version, ignore = "^bio-ceiling$", final_year = 2050, desired_regions = "All", desired_variables = "All",
  save_output = TRUE, output_file = file.path(scratch, "Ref_diag"), launch_ui = FALSE)
message("RUN9 DONE (no failure reproduced)")
