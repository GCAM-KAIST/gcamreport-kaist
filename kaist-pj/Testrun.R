# [2026-10-04: Claude code] new file: individual test runs of the kaist-pj pipeline steps 1~6 (fresh Rscript per step with a log, or in-session).
################################################################################
# Testrun.R - individual test runs of the kaist-pj pipeline (step1 ~ step6)
#
# source("C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-kaist/forked/kaist-pj/Testrun.R")
#   run_step(1)                    # one step in a fresh Rscript process, log in {output_dir}/logs/
#   run_step(5, args = "--checkpoints=A,B")
#   run_steps(2:6)                 # several steps in order, stops at the first failure
#   run_step(2, fresh = FALSE)     # source() in THIS session (interactive debugging; no args)
#   testrun_status()               # which inputs / outputs of each step exist right now
#
# A fresh process per step: step1/step2 call patch_gcam_data() + devtools::load_all() and the
# steps leave globals behind, so a clean R process is the reliable way to test one step at a
# time. Settings come from kaist-pj/core/config.R and kaist-pj/scenario/config.R as usual.
################################################################################

# --- package root (the folder with DESCRIPTION). Edit this line if the repo moves. ------
pkg_root <- "C:/Users/pjhan/Desktop/git/iam_models/GCAM/gcamreport-integrated/gcamreport-kaist/forked"
if (!file.exists(file.path(pkg_root, "DESCRIPTION"))) stop("Testrun.R: no DESCRIPTION at pkg_root = ", pkg_root)
setwd(pkg_root)
cat("Testrun: working directory set to", getwd(), "\n")

# --- the six steps --------------------------------------------------------------------
testrun_steps <- data.frame(
  step   = 1:6,
  script = c("kaist-pj/core/step1_generate_report.R", "kaist-pj/kmip/step2_process_data.R",
             "kaist-pj/kmip/step3_create_mapping.R",  "kaist-pj/kmip/step4_fill_template.R",
             "kaist-pj/kmip/step5_validate.R",        "kaist-pj/kmip/step6_plots.R"),
  needs  = c("BaseX database(s) from the scenario manifest + built data/*_v{version}.rda",
             "{run_name}.xlsx + newest {run_name}_project_*.dat (step1)",
             "{run_name}_korea.csv (step2) + KMIP template xlsx at template_path",
             "{run_name}_korea.csv (step2) + reviewed mapping xlsx at mapping_path + template",
             "any subset of the step1-4 outputs (missing ones are SKIPped)",
             "{run_name}_korea.csv (step2)"),
  stringsAsFactors = FALSE)

# --- helpers --------------------------------------------------------------------------
# config.R read into a private environment (run_name, output_dir, paths) without touching globals.
testrun_config <- function() {
  cfg <- new.env()
  suppressMessages(capture.output(source(file.path(getwd(), "kaist-pj/core/config.R"), local = cfg), type = "output"))
  cfg
}

.rscript_bin <- function() file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

# Run ONE step. fresh = TRUE: separate Rscript, stdout+stderr -> log file, last lines echoed.
# fresh = FALSE: source() in this session (no args, because step5 reads commandArgs()).
run_step <- function(step, args = character(), fresh = TRUE, tail_lines = 25) {
  s <- testrun_steps[testrun_steps$step == step, ]
  if (nrow(s) != 1) stop("step must be one of ", paste(testrun_steps$step, collapse = ", "))
  if (!fresh && length(args)) warning("args are ignored when fresh = FALSE (the script reads commandArgs())")
  cfg <- testrun_config()
  log_dir <- file.path(cfg$output_dir, "logs")
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
  log <- file.path(log_dir, sprintf("testrun_step%d_%s.log", step, format(Sys.time(), "%Y%m%d_%H%M%S")))
  cat(sprintf("\n================ step%d : %s ================\n", step, s$script))
  cat("needs :", s$needs, "\n")
  cat("run   :", cfg$run_name, "->", cfg$output_dir, "\n")
  if (fresh) cat("log   :", log, "\n")
  t0 <- Sys.time()
  if (fresh) {
    status <- system2(.rscript_bin(), c(shQuote(s$script), args), stdout = log, stderr = log)
    out <- readLines(log, warn = FALSE)
    cat(sprintf("--- last %d log lines ---\n", min(tail_lines, length(out))))
    cat(tail(out, tail_lines), sep = "\n")
  } else {
    status <- tryCatch({ source(s$script, echo = FALSE); 0L }, error = function(e) { message("step", step, " failed: ", conditionMessage(e)); 1L })
  }
  mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  ok <- identical(as.integer(status), 0L)
  cat(sprintf("================ step%d %s in %.1f min ================\n", step, if (ok) "OK" else sprintf("FAILED (exit status %s)", status), mins))
  invisible(list(step = step, ok = ok, status = status, minutes = mins, log = if (fresh) log else NA_character_))
}

# Run several steps in order; stops at the first failure unless stop_on_error = FALSE.
run_steps <- function(steps = 1:6, stop_on_error = TRUE, ...) {
  res <- list()
  for (st in steps) {
    r <- run_step(st, ...)
    res[[length(res) + 1]] <- data.frame(step = r$step, ok = r$ok, minutes = round(r$minutes, 1), log = r$log, stringsAsFactors = FALSE)
    if (!r$ok && stop_on_error) { cat("stopping: step", st, "failed\n"); break }
  }
  res <- do.call(rbind, res)
  cat("\n--- test run summary ---\n"); print(res, row.names = FALSE)
  invisible(res)
}

# Which inputs / outputs exist right now, per step.
testrun_status <- function() {
  cfg <- testrun_config()
  od <- cfg$output_dir; rn <- cfg$run_name
  newest <- function(pattern) {
    f <- list.files(od, pattern = pattern, full.names = TRUE)
    if (length(f) == 0) file.path(od, pattern) else f[order(file.mtime(f), decreasing = TRUE)[1]]
  }
  files <- c(
    "step1 report xlsx"       = file.path(od, paste0(rn, ".xlsx")),
    "step1 project .dat"      = newest(paste0("^", rn, "_project_.*\\.dat$")),
    "step2 all-regions csv"   = file.path(od, paste0(rn, ".csv")),
    "step2 Korea csv"         = file.path(od, paste0(rn, "_korea.csv")),
    "step3 input: template"   = cfg$template_path,
    "step3 output: mapping"   = cfg$mapping_path,
    "step4 before conversion" = file.path(od, "variables_before_unit_conversion.csv"),
    "step4 after conversion"  = file.path(od, "variables_after_unit_conversion.csv"),
    "step5 summary"           = file.path(od, "step5_summary.csv"),
    "step5 mismatches"        = file.path(od, "step5_mismatches.csv"),
    "step5 unmapped"          = file.path(od, "step5_unmapped.csv"),
    "step6 figure"            = file.path(od, paste0(rn, "_ghg_pathway.png")),
    "step6 series"            = file.path(od, paste0(rn, "_ghg_pathway.csv")))
  info <- file.info(files)
  tab <- data.frame(item = names(files), exists = ifelse(is.na(info$size), "-", "yes"),
                    modified = ifelse(is.na(info$mtime), "", format(info$mtime, "%Y-%m-%d %H:%M")),
                    file = basename(files), stringsAsFactors = FALSE)
  cat(sprintf("\nrun_name = %s | version = v%s | output_dir = %s\n", rn, cfg$version_number, od))
  if (exists("scenario_jobs", envir = cfg)) {
    sj <- get("scenario_jobs", envir = cfg)
    cat("scenario manifest:", paste(sprintf("%s (%s)", sj$scenario, sj$db), collapse = "; "), "\n")
  }
  print(tab, row.names = FALSE)
  if (identical(cfg$target_region, "All")) {
    cat("\nNOTE: target_region is \"All\" in kaist-pj/core/config.R; step2 Part B keeps only Region == target_region,",
        "so b1-b6, step3, step4 and step6 would work on an empty table. Set target_region <- \"South Korea\".\n")
  }
  invisible(tab)
}

##################### TEST ####################################
## Each call runs ONE step in a fresh Rscript; logs in {output_dir}/logs/. Uncomment to run.
run_step(1)                                   # query both u0909 databases (~30 min), merge for step2
# run_step(2)                                   # post-processing (needs step1 outputs)
# run_step(3)                                   # mapping template (needs the KMIP template xlsx)
# run_step(4)                                   # fill template (needs the reviewed mapping xlsx)
# run_step(5, args = "--checkpoints=A,B,C,D")   # validation; add "--strict" to fail on any FAIL
# run_step(6)                                   # GHG pathway figure
# run_steps(1:6)                                # whole chain, stop at first failure
# run_steps(2:6, stop_on_error = FALSE)         # everything after step1, report all results
# run_step(2, fresh = FALSE)                    # debug step2 inside this session instead
testrun_status()
