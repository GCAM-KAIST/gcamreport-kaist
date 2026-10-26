################################################################################
# Step 7: Comparison report against a reference run (e.g. the KMIP2025 submission)
#
# Renders kaist/kmip/step7_compare.qmd with quarto:
#   Part 1  all scenarios of this run against the reference scenarios
#           (GHG in the KMIP scope, national gross/net GHG, primary energy,
#           electricity, final energy by sector)
#   Part 2  one scenario pair, variable by variable (KMIP template names)
#
# INPUT:  compare_* settings in the KAIST_CONFIG file (see kaist/kmip/config/kaist9_low26.R),
#         {output_dir}/{run_name}_korea.csv (step2), variables_after_unit_conversion.csv (step4)
# OUTPUT: {output_dir}/compare/{run_name}_compare.pdf, one png + csv per section
# Quarto: `quarto` on PATH, or set QUARTO_BIN (RStudio Server ships one under
#         /usr/lib/rstudio-server/bin/quarto/bin/quarto).
################################################################################

########## Load configuration ##########
source(file.path(getwd(), "kaist/core/config.R"))
########################################

if (!exists("compare_a_file")) stop("step7: the settings file has no compare_a_file (reference run); nothing to compare")
if (!exists("compare_pair"))   stop("step7: the settings file has no compare_pair (c(a = ..., b = ...))")

# File names with Korean letters may be stored in NFD form: match NFC-normalized
resolve_nfc <- function(f) {
  if (file.exists(f)) return(f)
  cand <- list.files(dirname(f), full.names = TRUE)
  hit <- cand[stringi::stri_trans_nfc(basename(cand)) == stringi::stri_trans_nfc(basename(f))]
  if (length(hit) > 0) hit[1] else f
}
compare_a_file <- resolve_nfc(compare_a_file)

out_dir  <- file.path(output_dir, "compare")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
b_step4  <- file.path(output_dir, "variables_after_unit_conversion.csv")
b_korea  <- file.path(output_dir, paste0(run_name, "_korea.csv"))
for (f in c(compare_a_file, b_step4, b_korea))
  if (!file.exists(f)) stop("step7: missing input ", f)

params <- list(
  a_file       = compare_a_file,
  a_model      = get0("compare_a_model", ifnotfound = "GC"),
  a_label      = get0("compare_a_label", ifnotfound = "Reference"),
  a_scenarios  = as.list(get0("compare_a_scenarios", ifnotfound = character(0))),
  b_label      = get0("compare_b_label", ifnotfound = run_name),
  b_step4      = b_step4,
  b_korea      = b_korea,
  b_scenarios  = as.list(get0("compare_b_scenarios", ifnotfound = scenarios)),
  pair_a       = unname(compare_pair[["a"]]),
  pair_b       = unname(compare_pair[["b"]]),
  ref_step2_csv = get0("compare_ref_step2_csv", ifnotfound = ""),
  out_dir      = out_dir,
  save_png     = TRUE
)
yml <- file.path(out_dir, "params.yml")
# write TRUE/FALSE as true/false (yaml's default "yes"/"no" reaches quarto as text)
yaml::write_yaml(params, yml, handlers = list(logical = function(x) {
  r <- ifelse(x, "true", "false"); class(r) <- "verbatim"; r }))

# quarto binary
qb <- Sys.getenv("QUARTO_BIN")
if (qb == "") qb <- unname(Sys.which("quarto"))
if (qb == "" && requireNamespace("quarto", quietly = TRUE)) qb <- quarto::quarto_path()
if (qb == "" && file.exists("/usr/lib/rstudio-server/bin/quarto/bin/quarto"))
  qb <- "/usr/lib/rstudio-server/bin/quarto/bin/quarto"
if (qb == "" || is.na(qb)) stop("step7: quarto not found; set QUARTO_BIN")

qmd     <- file.path(getwd(), "kaist/kmip/step7_compare.qmd")
pdf_nm  <- paste0(run_name, "_compare.pdf")
cat("Rendering", basename(qmd), "->", file.path(out_dir, pdf_nm), "\n")
st <- system2(qb, c("render", shQuote(qmd), "--to", "pdf", "--execute-params", shQuote(yml),
                    "--output", shQuote(pdf_nm)))
if (st != 0) stop("step7: quarto render failed (exit ", st, ")")
# quarto writes --output relative to the working directory (older versions: next to the qmd)
made <- c(file.path(getwd(), pdf_nm), file.path(dirname(qmd), pdf_nm))
made <- made[file.exists(made)]
if (length(made) == 0) stop("step7: rendered pdf not found")
file.rename(made[1], file.path(out_dir, pdf_nm))

cat("\n=== Step 7 Complete ===\nReport:", file.path(out_dir, pdf_nm), "\nSections (png, csv):", out_dir, "\n")
