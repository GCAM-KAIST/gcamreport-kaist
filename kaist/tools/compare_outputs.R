################################################################################
# compare_outputs.R -- verify that a refactored step produces identical output
#
# Usage (from the repo root):
#   source("kaist/tools/compare_outputs.R")
#   compare_csv("path/to/baseline.csv", "path/to/new.csv")
#
# Returns TRUE when the files are identical (md5 match), otherwise prints a
# diagnosis of what differs and returns FALSE. Used during the step2 module
# refactor to prove each extraction changed nothing.
################################################################################

compare_csv <- function(old_path, new_path, tol = 0) {
  if (!file.exists(old_path)) stop("Baseline file not found: ", old_path)
  if (!file.exists(new_path)) stop("New file not found: ", new_path)

  # Fast path: byte-identical files
  sums <- tools::md5sum(c(old_path, new_path))
  if (sums[[1]] == sums[[2]]) {
    cat("IDENTICAL (md5):", basename(new_path), "\n")
    return(invisible(TRUE))
  }

  cat("md5 differs -- diagnosing", basename(new_path), "...\n")
  old <- utils::read.csv(old_path, check.names = FALSE, stringsAsFactors = FALSE)
  new <- utils::read.csv(new_path, check.names = FALSE, stringsAsFactors = FALSE)

  if (!identical(names(old), names(new))) {
    cat("  Column mismatch.\n")
    cat("    only in baseline:", paste(setdiff(names(old), names(new)), collapse = ", "), "\n")
    cat("    only in new     :", paste(setdiff(names(new), names(old)), collapse = ", "), "\n")
    return(invisible(FALSE))
  }
  if (nrow(old) != nrow(new)) {
    cat("  Row count mismatch: baseline", nrow(old), "vs new", nrow(new), "\n")
  }

  # Compare on sorted keys so pure row-order changes are reported as such
  key_cols <- intersect(c("Model", "Scenario", "Region", "Variable", "Unit"), names(old))
  key <- function(df) do.call(paste, c(df[key_cols], sep = "\r"))
  old_key <- key(old); new_key <- key(new)

  only_old <- setdiff(old_key, new_key)
  only_new <- setdiff(new_key, old_key)
  if (length(only_old) > 0) {
    cat("  Rows only in baseline:", length(only_old), "e.g.\n   ",
        paste(utils::head(gsub("\r", " | ", only_old), 3), collapse = "\n    "), "\n")
  }
  if (length(only_new) > 0) {
    cat("  Rows only in new:", length(only_new), "e.g.\n   ",
        paste(utils::head(gsub("\r", " | ", only_new), 3), collapse = "\n    "), "\n")
  }

  common <- intersect(old_key, new_key)
  if (anyDuplicated(old_key[old_key %in% common]) || anyDuplicated(new_key[new_key %in% common])) {
    cat("  Note: duplicated key rows exist; value comparison uses first match per key.\n")
  }
  old_c <- old[match(common, old_key), , drop = FALSE]
  new_c <- new[match(common, new_key), , drop = FALSE]

  num_cols <- names(old)[vapply(old, is.numeric, logical(1))]
  n_bad_rows <- 0
  for (i in seq_len(nrow(old_c))) {
    ov <- as.numeric(old_c[i, num_cols]); nv <- as.numeric(new_c[i, num_cols])
    diff <- abs(ov - nv)
    diff[is.na(ov) & is.na(nv)] <- 0
    diff[xor(is.na(ov), is.na(nv))] <- Inf
    if (any(diff > tol, na.rm = TRUE)) {
      n_bad_rows <- n_bad_rows + 1
      if (n_bad_rows <= 5) {
        bad_col <- num_cols[which(diff > tol)[1]]
        cat("  DIFF:", gsub("\r", " | ", common[i]),
            "| col", bad_col, ": baseline =", old_c[i, bad_col],
            ", new =", new_c[i, bad_col], "\n")
      }
    }
  }
  if (n_bad_rows > 5) cat("  ... and", n_bad_rows - 5, "more differing rows\n")
  if (n_bad_rows == 0 && length(only_old) == 0 && length(only_new) == 0) {
    cat("  Same content, different byte layout (row order or number formatting).\n")
  }
  invisible(FALSE)
}

# Convenience wrapper: compare both step2 outputs against a baseline directory.
compare_step2_outputs <- function(baseline_dir, output_dir, run_name) {
  files <- paste0(run_name, c(".csv", "_korea.csv"))
  ok <- TRUE
  for (f in files) {
    ok <- isTRUE(compare_csv(file.path(baseline_dir, f), file.path(output_dir, f))) && ok
  }
  invisible(ok)
}
