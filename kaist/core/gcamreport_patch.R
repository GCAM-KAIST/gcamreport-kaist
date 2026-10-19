# [2026-10-04: Claude code] new file: runtime namespace patch for gcamreport-temp fix 8 (is_ignored() guard in get_co2_price_fragmented_tmp).
################################################################################
# gcamreport_patch.R - runtime patches to the loaded gcamreport namespace
#
# Companion of rgcam_patch.R and of patch_gcam_data() (functions.R): the
# package source under R/ stays byte-identical to upstream bc3LC/gcamreport,
# and the KAIST-side fixes are re-applied here at runtime.
#
# HOW TO USE:
#   Source this file AFTER devtools::load_all(".", reset = TRUE) -- the
#   gcamreport namespace must exist. step1_generate_report.R, the step1 tools
#   and run_scenarios.R already do so.
#
# PATCH 1 -- is_ignored() guard in get_co2_price_fragmented_tmp()
#   ("fix 8" in gcamreport-temp/debug/case1_chemical_feedback_Sector/
#    Error_Log/README.md, section 5b)
#
#   Upstream filters CO2 price markets twice with
#     dplyr::filter(!grepl(paste(.myGlobals$ignore.global, collapse = "|"), market))
#   When generate_report() is called without `ignore`, ignore.global is NULL,
#   paste(NULL, collapse = "|") is "" and grepl("", x) is TRUE for every x, so
#   EVERY CO2 price market is dropped. The function then sees <= 1 row, sets
#   co2_price_fragmented to NULL, and Price|Carbon / Revenue|Government come
#   out as 0 in all regions (seen on the KAIST NZ scenario; the core v9.1
#   Reference has no CO2 price market, which is why Testrun.R never showed it).
#
#   The patch replaces both filters by `!is_ignored(market)` where is_ignored()
#   returns FALSE for everything when no pattern is set and is otherwise the
#   original grepl(). Behaviour with a non-empty `ignore` is unchanged.
#
#   Mechanics: the function body is taken from the loaded namespace, the two
#   filter expressions are rewritten textually, and the rebuilt function is put
#   back into the namespace (and into the attached package env). The namespace
#   is locked against NEW bindings, so is_ignored() lives in a small child
#   environment of the namespace that the patched function uses as its
#   enclosure -- every other symbol still resolves in the namespace as before.
#   If upstream adopts the fix (an `is_ignored` already exists, or the pattern
#   is gone), the patch detects it and does nothing.
################################################################################

patch_gcamreport_functions <- function(verbose = TRUE) {
  if (!"gcamreport" %in% loadedNamespaces()) {
    stop("gcamreport_patch.R: gcamreport is not loaded. Run devtools::load_all('.') first.")
  }
  ns <- asNamespace("gcamreport")
  say <- function(...) if (verbose) cat(...)

  # --- Patch 1: is_ignored() guard ------------------------------------------
  fn_name <- "get_co2_price_fragmented_tmp"
  old_expr <- '!grepl(paste(.myGlobals$ignore.global, collapse = "|"), market)'
  new_expr <- "!is_ignored(market)"

  if (exists("is_ignored", envir = ns, inherits = FALSE)) {
    say("gcamreport_patch: upstream already defines is_ignored() -- patch 1 skipped.\n")
    return(invisible(FALSE))
  }
  if (!exists(fn_name, envir = ns, inherits = FALSE)) {
    warning("gcamreport_patch: ", fn_name, "() not found in gcamreport -- patch 1 skipped.")
    return(invisible(FALSE))
  }

  f <- get(fn_name, envir = ns)
  txt <- paste(deparse(f, width.cutoff = 500L), collapse = "\n")
  n_hits <- lengths(regmatches(txt, gregexpr(old_expr, txt, fixed = TRUE)))
  if (n_hits == 0) {
    say("gcamreport_patch: ignore-filter pattern not found in ", fn_name,
        "() -- upstream code changed, patch 1 skipped.\n")
    return(invisible(FALSE))
  }

  patched_env <- new.env(parent = ns)
  patched_env$is_ignored <- function(x) {
    ig <- .myGlobals$ignore.global
    if (length(ig) == 0) return(rep(FALSE, length(x)))
    grepl(paste(ig, collapse = "|"), x)
  }
  environment(patched_env$is_ignored) <- patched_env

  new_f <- eval(parse(text = gsub(old_expr, new_expr, txt, fixed = TRUE)))
  environment(new_f) <- patched_env

  targets <- list(ns)
  if ("package:gcamreport" %in% search()) {
    targets <- c(targets, list(as.environment("package:gcamreport")))
  }
  for (e in targets) {
    if (!exists(fn_name, envir = e, inherits = FALSE)) next
    was_locked <- bindingIsLocked(fn_name, e)
    if (was_locked) unlockBinding(fn_name, e)
    assign(fn_name, new_f, envir = e)
    if (was_locked) lockBinding(fn_name, e)
  }

  say(sprintf("gcamreport_patch: %s() patched (%d ignore filter(s) -> is_ignored()).\n",
              fn_name, n_hits))
  invisible(TRUE)
}

patch_gcamreport_functions()
