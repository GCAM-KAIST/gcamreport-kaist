# SOFT SCAN: run generate_report on the Ref project with left_join_strict temporarily patched so that
# unmatched mapping keys are LOGGED and dropped instead of aborting. Purpose: find every missing
# mapping key in one pass. Output is written to a scratch folder, not to the report folder.
setwd("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp")
devtools::load_all(".", reset = TRUE)
suppressMessages(library(dplyr))
.scan <- new.env(); .scan$log <- list()
left_join_strict_soft <- function(left_df, right_df, by = NULL, by_message = by, mapping = "",
                                  ignore = if (exists("ignore.global", envir = .myGlobals)) .myGlobals$ignore.global else NULL, ...) {
  if (mapping == "") mapping <- paste0("<", paste(deparse(substitute(right_df)), collapse = "")[1], ">")
  result <- dplyr::left_join(left_df, right_df, by = by, ...)
  unmatched <- result %>% dplyr::filter(dplyr::if_any(-dplyr::one_of(names(left_df)), is.na))
  if (!is.null(ignore) & nrow(unmatched) > 0) {
    unmatched_ignore <- unmatched %>% dplyr::filter(dplyr::if_any(.cols = dplyr::everything(), ~ grepl(paste(ignore, collapse = "|"), .)))
    unmatched <- suppressMessages(unmatched %>% dplyr::anti_join(unmatched_ignore))
    result <- suppressMessages(result %>% dplyr::anti_join(unmatched_ignore))
  }
  if (nrow(unmatched) > 0) {
    details <- try(unique(unmatched %>% dplyr::select(dplyr::all_of(unname(by_message)))), silent = TRUE)
    if (inherits(details, "try-error")) details <- unique(unmatched[, intersect(names(unmatched), unname(by_message)), drop = FALSE])
    .scan$log[[length(.scan$log) + 1]] <- list(mapping = mapping, keys = details)
    message(sprintf("SOFTSCAN mapping=%s missing %d key(s): %s", substr(mapping, 1, 60), nrow(details),
                    paste(apply(as.data.frame(details), 1, paste, collapse = " / "), collapse = " ; ")))
    result <- suppressMessages(result %>% dplyr::anti_join(unmatched))
  }
  result
}
environment(left_join_strict_soft) <- asNamespace("gcamreport")
ns <- asNamespace("gcamreport"); unlockBinding("left_join_strict", ns)
assign("left_join_strict", left_join_strict_soft, envir = ns); lockBinding("left_join_strict", ns)
if (exists("left_join_strict", envir = as.environment("package:gcamreport"))) { pe <- as.environment("package:gcamreport"); unlockBinding("left_join_strict", pe); assign("left_join_strict", left_join_strict_soft, envir = pe) }
dump_scan <- function() {
  cat("\n=== SOFTSCAN SUMMARY (", length(.scan$log), " unmatched events) ===\n")
  for (e in .scan$log) { cat("mapping:", e$mapping, "\n"); print(as.data.frame(e$keys)) }
  saveRDS(.scan$log, "debug/case1_chemical_feedback_Sector/Error_Log/run4_softscan_ref.rds")
}
options(error = quote({ cat("\n=== ERROR HOOK ===\n"); dump_scan(); q(status = 1) }))
db_path <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-temp/debug/case1_chemical_feedback_Sector/Input"
scratch <- "C:/Users/pjhan/AppData/Local/Temp/claude/c--Users-pjhan-Desktop-git/96158667-f862-496a-a5bf-afb808a83a36/scratchpad/softscan"
dir.create(scratch, recursive = TRUE, showWarnings = FALSE)
generate_report(db_path = db_path, db_name = "u0909r", prj_name = file.path(db_path, "u0909r_Ref_u0909.dat"),
  scenarios = "KAIST_9_ref_u0909", GCAM_version = "v9.1", ignore = "^bio-ceiling$", final_year = 2050,
  desired_regions = "All", desired_variables = "All", save_output = TRUE,
  output_file = file.path(scratch, "Ref_softscan"), launch_ui = FALSE)
dump_scan(); message("RUN4 DONE")
