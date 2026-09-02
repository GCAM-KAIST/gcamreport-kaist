################################################################################
# step1_parallel: run step1 with one worker process per scenario, then merge.
#
# Usage (from the repo root):
#   Rscript kaist/tools/step1_parallel.R [--jobs=N] [--dry-run]
# Scenarios come from kaist/config.R. --jobs caps how many workers run at
# once (default: all). Logs: {output_dir}/logs/step1_{scenario}.log
# Replaces: Rscript kaist/step1_generate_report.R (single process).
################################################################################

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args
jobs_arg <- grep("^--jobs=", args, value = TRUE)

source(file.path(getwd(), "kaist/config.R"))
jobs <- if (length(jobs_arg) > 0) as.integer(sub("^--jobs=", "", jobs_arg[1])) else length(scenarios)
jobs <- max(1L, min(jobs, length(scenarios)))

log_dir <- file.path(output_dir, "logs")
if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

cat(sprintf("step1_parallel: %d scenario(s), %d at a time\n", length(scenarios), jobs))
cat("  scenarios:", paste(scenarios, collapse = ", "), "\n")

if (dry_run) {
  for (s in scenarios) cat("  would run: Rscript kaist/tools/step1_worker.R", shQuote(s), "\n")
  cat("  then: Rscript kaist/tools/step1_merge.R\n")
  quit(status = 0)
}

# patch data/*.rda once here; workers skip it
patch_gcam_data(paste0("v", version_number))

# launch workers, at most `jobs` at a time
running <- list()
failed <- character(0)
t0 <- Sys.time()

launch <- function(s) {
  log <- file.path(log_dir, paste0("step1_", s, ".log"))
  cat(sprintf("  [%s] start %s -> %s\n", format(Sys.time(), "%H:%M:%S"), s, basename(log)))
  p <- processx::process$new("Rscript", c("kaist/tools/step1_worker.R", s),
                             stdout = log, stderr = "2>&1")
  list(scenario = s, proc = p)
}

queue <- scenarios
while (length(queue) > 0 || length(running) > 0) {
  while (length(queue) > 0 && length(running) < jobs) {
    running[[length(running) + 1]] <- launch(queue[1])
    queue <- queue[-1]
  }
  Sys.sleep(5)
  still <- list()
  for (r in running) {
    if (r$proc$is_alive()) { still[[length(still) + 1]] <- r; next }
    st <- r$proc$get_exit_status()
    cat(sprintf("  [%s] done  %s (exit %d)\n", format(Sys.time(), "%H:%M:%S"), r$scenario, st))
    if (st != 0) failed <- c(failed, r$scenario)
  }
  running <- still
}
cat(sprintf("workers finished in %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

if (length(failed) > 0) {
  stop("step1 worker(s) failed: ", paste(failed, collapse = ", "),
       " -- see ", log_dir)
}

cat("merging ...\n")
st <- system2("Rscript", "kaist/tools/step1_merge.R")
if (st != 0) stop("step1_merge.R failed (exit ", st, ")")
cat("\n=== step1_parallel complete ===\nNext: Rscript kaist/step2_process_data.R\n")
