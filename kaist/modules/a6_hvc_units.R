################################################################################
# a6: Fix Production|Chemicals|High-Value Chemicals unit
#
# gcamreport bug: EJ values are labeled as Mt/yr without conversion
# See: https://github.com/bc3LC/gcamreport - functions.R line 5752-5762
# The inner_join with template assigns Unit from template without converting values
#
# GCAM output units (from production_map):
#   - ammonia -> Mt NH3 (correct)
#   - chemical -> EJ (WRONG - labeled as Mt/yr in template)
#   - N fertilizer -> Mt N (correct)
#
# Fix: Change Unit from "Mt/yr" to "EJ/yr" for High-Value Chemicals only
################################################################################

fix_hvc_units <- function(data) {
  hvc_idx <- which(data$Variable == "Production|Chemicals|High-Value Chemicals")
  if (length(hvc_idx) > 0) {
    data[hvc_idx, "Unit"] <- "EJ/yr"
    cat("Fixed unit for Production|Chemicals|High-Value Chemicals: Mt/yr -> EJ/yr\n")
  }
  data
}
