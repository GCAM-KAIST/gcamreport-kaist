################################################################################
# unavailable_query.R - .dat 없이 DB에서 직접 쿼리 가능 여부 확인
#
# gcamreport의 76개 쿼리를 DB에 직접 실행해서 어떤 것이 빈 결과인지 파악.
# 그 결과를 var_fun_map(원본 CSV)과 매칭해서 saveDataFiles 필터 제안.
#
# Usage:
#   source("kaist/unavailable_query.R")
#
# Prerequisites:
#   - GCAM BaseX DB 접근 가능, Java 설치
################################################################################

library(dplyr)
library(readr)
library(xml2)

# === 설정 (직접 수정) ===
db_path <- "C:/GCAM/gcamreport/kmip"
db_name <- "DB26"
test_region <- c("South Korea", "Russia", "USA")  # "ALL" = 전체, 또는 "South Korea" 등 특정 region
test_scenarios <- c("S1", "S08")        # "ALL" = 전체, 또는 c("S1", "S08") 등 특정 시나리오

# === BaseX engine ===
.mi_classpath <- rgcam:::DEFAULT.MICLASSPATH()
.max_memory <- "4g"

run_basex <- function(xquery_string, csv_format = NULL) {
  tmp_query_fn <- tempfile(fileext = ".xq")
  tmp_output_fn <- tempfile(fileext = ".csv")
  on.exit({ unlink(tmp_query_fn); unlink(tmp_output_fn) })

  writeLines(xquery_string, tmp_query_fn)

  csv_opts <- "-scsv=header=yes"
  if (!is.null(csv_format)) csv_opts <- paste0(csv_opts, ",format=", csv_format)

  cmd_args <- c(
    paste("-cp", shQuote(.mi_classpath)),
    paste0("-Xmx", .max_memory),
    paste0("-Dorg.basex.DBPATH=", shQuote(db_path)),
    "-DModelInterface.SUPPRESS_OUTPUT=true",
    "org.basex.BaseX",
    "-smethod=csv",
    csv_opts,
    paste0("-o", shQuote(tmp_output_fn)),
    "-c", shQuote(paste0("OPEN ", db_name, "; RUN ", tmp_query_fn))
  )

  system2("java", args = paste(cmd_args, collapse = " "),
          stdout = FALSE, stderr = FALSE)
  tryCatch(
    read_csv(tmp_output_fn, col_types = cols(), show_col_types = FALSE),
    error = function(e) tibble::tibble()
  )
}

test_mi_query <- function(query_xml, scenarios, regions = NULL) {
  xqScenarios <- paste0("('", paste(scenarios, collapse = "','"), "')")
  xqRegion <- if (is.null(regions)) "()" else
    paste0("('", paste(regions, collapse = "','"), "')")

  query_xml <- gsub("\n", "", query_xml)
  query_xml <- gsub("\\s+", " ", query_xml)

  # 결과가 있는지만 확인 (1행이라도 있으면 OK)
  xquery <- paste0(
    "import module namespace mi = 'ModelInterface.ModelGUI2.xmldb.RunMIQuery';",
    "let $r := mi:runMIQuery(", query_xml, ",", xqScenarios, ",", xqRegion, ") ",
    "return if (exists($r)) then 'HAS_DATA' else 'EMPTY'"
  )

  tmp_query_fn <- tempfile(fileext = ".xq")
  tmp_output_fn <- tempfile(fileext = ".txt")
  on.exit({ unlink(tmp_query_fn); unlink(tmp_output_fn) })

  writeLines(xquery, tmp_query_fn)

  cmd_args <- c(
    paste("-cp", shQuote(.mi_classpath)),
    paste0("-Xmx", .max_memory),
    paste0("-Dorg.basex.DBPATH=", shQuote(db_path)),
    "-DModelInterface.SUPPRESS_OUTPUT=true",
    "org.basex.BaseX",
    paste0("-o", shQuote(tmp_output_fn)),
    "-c", shQuote(paste0("OPEN ", db_name, "; RUN ", tmp_query_fn))
  )

  system2("java", args = paste(cmd_args, collapse = " "),
          stdout = FALSE, stderr = FALSE)
  out <- tryCatch(readLines(tmp_output_fn, warn = FALSE), error = function(e) "")
  grepl("HAS_DATA", paste(out, collapse = ""))
}

# === DB 시나리오 확인 ===
cat("Connecting to DB:", db_name, "at", db_path, "\n")
scen_xq <- paste0(
  'let $scns := collection()/scenario ',
  'return document{ element csv { ',
  'for $scn in $scns return element record { ',
  'element name { text { $scn/@name } }, ',
  'element date { text { $scn/@date } } } } }'
)
scen_df <- run_basex(scen_xq)
scen_df <- scen_df[!duplicated(scen_df$name, fromLast = TRUE), ]
cat("DB scenarios:", paste(scen_df$name, collapse = ", "), "\n")

# 시나리오 설정
if (length(test_scenarios) == 1 && toupper(test_scenarios) == "ALL") {
  scenarios <- scen_df$name
} else {
  scenarios <- test_scenarios
}
cat("Testing scenarios:", paste(scenarios, collapse = ", "), "\n")

# region 설정
query_regions <- if (length(test_region) == 1 && toupper(test_region) == "ALL") NULL else test_region
cat("Region:", if (is.null(query_regions)) "ALL" else query_regions, "\n\n")

# === gcamreport 쿼리 XML 파싱 ===
queries_file <- file.path(getwd(), "inst/extdata/queries/GCAM7.0/queries_gcamreport_general.xml")
qxml <- read_xml(queries_file)
q_nodes <- xml_find_all(qxml, "//*[self::supplyDemandQuery or self::emissionsQueryBuilder or self::ClimateQuery][@title]")
q_titles <- xml_attr(q_nodes, "title")
cat("Testing", length(q_titles), "gcamreport queries...\n\n")

# === 각 쿼리 테스트 ===
results <- data.frame(
  query = q_titles, status = NA_character_,
  stringsAsFactors = FALSE
)

for (i in seq_along(q_titles)) {
  cat(sprintf("[%02d/%02d] %-55s ", i, length(q_titles), q_titles[i]))

  query_xml <- as.character(q_nodes[[i]])

  has_data <- tryCatch(
    test_mi_query(query_xml, scenarios, query_regions),
    error = function(e) NA
  )

  if (isTRUE(has_data)) {
    results$status[i] <- "OK"
    cat("OK\n")
  } else if (isFALSE(has_data)) {
    results$status[i] <- "EMPTY"
    cat("EMPTY\n")
  } else {
    results$status[i] <- "ERROR"
    cat("ERROR\n")
  }
}

# === var_fun_map 원본 CSV (필터 안 된 버전) ===
vfm_csv <- read.csv(
  file.path(getwd(), "inst/extdata/mappings/GCAM7.0/variables_functions_mapping.csv"),
  sep = ";", header = TRUE, na.strings = c("", "NA")
)
vfm_csv$queries_list <- strsplit(as.character(vfm_csv$queries), ",")

# === 매칭: 빈 쿼리 → 영향받는 변수 ===
empty_queries <- results$query[results$status != "OK"]

affected_vars <- c()
for (j in 1:nrow(vfm_csv)) {
  qs <- trimws(vfm_csv$queries_list[[j]])
  if (any(qs %in% empty_queries & !is.na(qs))) {
    affected_vars <- c(affected_vars, vfm_csv$name[j])
  }
}

# dependency 추적
all_affected <- affected_vars
for (j in 1:nrow(vfm_csv)) {
  deps <- trimws(strsplit(as.character(vfm_csv$dependencies[j]), ",")[[1]])
  if (any(deps %in% all_affected & !is.na(deps))) {
    if (!vfm_csv$name[j] %in% all_affected) {
      all_affected <- c(all_affected, vfm_csv$name[j])
    }
  }
}

# 7.1+ 전용 변수
v71_only <- c("income_clean", "consumption_hh_clean")
all_affected <- unique(c(v71_only, all_affected))

# === 결과 출력 ===
cat("\n===========================================================\n")
cat("  RESULTS\n")
cat("===========================================================\n\n")

ok <- sum(results$status == "OK")
empty <- sum(results$status == "EMPTY")
err <- sum(results$status == "ERROR")
cat(sprintf("  Queries OK:    %d / %d\n", ok, nrow(results)))
cat(sprintf("  Queries EMPTY: %d\n", empty))
cat(sprintf("  Queries ERROR: %d\n\n", err))

if (length(empty_queries) > 0) {
  cat("--- Unavailable queries ---\n")
  for (eq in empty_queries) {
    users <- c()
    for (j in 1:nrow(vfm_csv)) {
      qs <- trimws(vfm_csv$queries_list[[j]])
      if (eq %in% qs) users <- c(users, vfm_csv$name[j])
    }
    cat(sprintf("  %-60s → %s\n", eq, paste(users, collapse = ", ")))
  }
}

if (length(all_affected) > 0) {
  cat("\n--- Variables to filter from template ---\n")
  direct <- all_affected[all_affected %in% affected_vars | all_affected %in% v71_only]
  indirect <- setdiff(all_affected, direct)
  for (v in direct) cat(sprintf("  %s\n", v))
  for (v in indirect) cat(sprintf("  %s  (dependency)\n", v))

  cat("\n--- Copy-paste for saveDataFiles_GCAM7.0.R ---\n")
  cat(sprintf('dplyr::filter(!Internal_variable %%in%% c(%s))\n',
              paste(sprintf('"%s"', all_affected), collapse = ", ")))
}

cat("\n===========================================================\n")
