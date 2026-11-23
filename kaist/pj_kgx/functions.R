################################################################################
# pj_kgx project functions. Sourced by the pj_kgx settings files.
#
# kaist/core/functions.R is sourced here too, because the settings file needs
# kaist_ignore_markets before config.R loads the core functions (sourcing it
# twice only redefines the same objects).
################################################################################

source(file.path(getwd(), "kaist/core/functions.R"))

# K-ETS markets of the K-GX fund runs: the face-value market <region>CO2_KETS and the class
# markets <region>CO2_KETS_<class>. gcamreport's co2_market mapping knows <region>CO2 only, so
# step1 drops them (ignore) and build_kgx_report.R reports them.
kgx_ignore_markets <- "CO2_KETS"

# Classes of kgx_classes.csv: suffix -> class name. Stops on a class market the file does not list.
read_kgx_classes <- function(file) {
  cls <- utils::read.csv(file, comment.char = "#", stringsAsFactors = FALSE, strip.white = TRUE)
  stopifnot(all(c("suffix", "class") %in% names(cls)), !anyDuplicated(cls$suffix), !anyDuplicated(cls$class))
  cls
}
