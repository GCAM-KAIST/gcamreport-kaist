################################################################################
# rgcam_patch.R - BaseX Compatibility Fix for rgcam Package
#
# PROBLEM:
#   rgcam may fail with: "Database does not exist or is invalid" error.
#
#   Root cause: rgcam uses the "-i" flag to open BaseX databases, but the
#   "-i" flag behavior changed in BaseX 9.5+. The rgcam package bundles
#   BaseX 9.5.0, but the code still uses the old "-i" syntax which now
#   returns empty results instead of opening the database.
#
# SOLUTION:
#   This patch replaces the "-i DB" syntax with "-c 'OPEN DB; XQUERY/RUN ...'"
#   which works correctly in BaseX 9.5+.
#
# WHEN TO USE:
#   - If you get "Database does not exist or is invalid" error
#   - If rgcam::localDBConn() fails but the database files exist
#
# HOW TO USE:
#   Add this line in your script AFTER loading rgcam:
#     library(rgcam)
#     source(file.path(getwd(), "rgcam_patch.R"))
#
# REFERENCE:
#   GitHub Issue: https://github.com/JGCRI/rgcam/issues/92
#
################################################################################

library(rgcam)

# Create patched version of listScenariosInDB.localDBConn
listScenariosInDB_patched <- function(dbConn) {
  tmp_output_fn <- tempfile()

  # XQuery to get scenarios
  xquery <- 'let $scns := collection()/scenario return document{ element csv { for $scn in $scns return element record { element name  { text { $scn/@name } }, element date { text { $scn/@date } }, element version { text{ $scn/model-version/text() } } } } }'

  cmd_args <- c(
    paste("-cp", shQuote(dbConn$miclasspath)),
    paste0("-Xmx", dbConn$maxMemory),
    paste0("-Dorg.basex.DBPATH=", shQuote(dbConn$dbPath)),
    "org.basex.BaseX",
    "-smethod=csv",
    "-scsv=header=yes",
    paste0("-o", shQuote(tmp_output_fn)),
    "-c", shQuote(paste0("OPEN ", dbConn$dbFile, "; XQUERY ", xquery))
  )

  system2("java", args = paste(cmd_args, collapse = " "))
  result <- readr::read_csv(tmp_output_fn, col_types = readr::cols(
    name = readr::col_character(),
    date = readr::col_character(),
    version = readr::col_character()
  ), show_col_types = FALSE)
  unlink(tmp_output_fn)

  if (nrow(result) > 0) {
    result <- dplyr::mutate(result, fqName = paste(name, date, sep = " "))
  }
  result
}

# Create patched version of runQuery.localDBConn
runQuery_patched <- function(dbConn, query, scenarios = NULL, regions = NULL, warn.empty = TRUE) {
  xqScenarios <- ifelse(length(scenarios) == 0, "()",
                        paste0("('", paste(scenarios, collapse = "','"), "')"))
  xqRegion <- ifelse(length(regions) == 0, "()",
                     paste0("('", paste(regions, collapse = "','"), "')"))

  query <- gsub("\n", "", query)
  query <- gsub("\\s+", " ", query)

  tmp_query_fn <- tempfile()
  tmp_output_fn <- tempfile()

  # Write query to temp file
  tmp_query_conn <- file(tmp_query_fn, open = "w")
  cat(paste0("import module namespace mi = 'ModelInterface.ModelGUI2.xmldb.RunMIQuery';",
             "mi:runMIQuery(", query, ",", xqScenarios, ",", xqRegion, ")"),
      file = tmp_query_conn, sep = "\n")
  close(tmp_query_conn)

  # Fixed: Use -c 'OPEN DB; RUN queryfile' instead of -i DB RUN queryfile
  cmd_args <- c(
    paste("-cp", shQuote(dbConn$miclasspath)),
    paste0("-Xmx", dbConn$maxMemory),
    paste0("-Dorg.basex.DBPATH=", shQuote(dbConn$dbPath)),
    paste0("-DModelInterface.SUPPRESS_OUTPUT=", dbConn$migabble),
    "org.basex.BaseX",
    "-smethod=csv",
    "-scsv=header=yes,format=xquery",
    paste0("-o", shQuote(tmp_output_fn)),
    "-c", shQuote(paste0("OPEN ", dbConn$dbFile, "; RUN ", tmp_query_fn))
  )

  if (dbConn$migabble) {
    suppress_col_spec <- readr::cols()
  } else {
    suppress_col_spec <- NULL
  }

  system2("java", args = paste(cmd_args, collapse = " "))
  results <- readr::read_csv(tmp_output_fn, col_types = suppress_col_spec, show_col_types = FALSE)

  unlink(tmp_query_fn)
  unlink(tmp_output_fn)

  rgcam:::miquery_post(results, query, scenarios, regions, warn.empty)
}

# Monkey-patch rgcam namespace
assignInNamespace("listScenariosInDB.localDBConn", listScenariosInDB_patched, ns = "rgcam")
assignInNamespace("runQuery.localDBConn", runQuery_patched, ns = "rgcam")

cat("rgcam patched successfully!\n")
cat("BaseX compatibility fix applied (OPEN command instead of -i flag)\n")
