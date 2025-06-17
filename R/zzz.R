.myGlobals <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  .myGlobals$ignore.global <- NULL
  .myGlobals$interactive.global <- NULL
  .myGlobals$variables.global <- NULL
  .myGlobals$GCAM_version <- NULL
}
