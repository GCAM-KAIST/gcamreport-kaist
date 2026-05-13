################################################################################
# GCAM Query Browser (Without .dat)
#
# PURPOSE:
#   .dat 캐시 파일 없이 Main_queries.xml의 쿼리를 BaseX DB에서 직접 실행.
#   rgcam_patch.R 없이 BaseX 9.5+ 호환 명령을 자체 구현.
#
# USAGE:
#   source("kaist/query_browser_without_dat.R")
#
#   list_scenarios()                    # DB의 시나리오 목록 (중복 제거)
#   list_all_queries()                  # 전체 쿼리 목록
#   list_all_queries("elec")            # 이름으로 필터
#   run_db_query(10)                    # 10번 쿼리 실행 (전체 시나리오)
#   run_db_query(10, c("S1","S08"))     # 특정 시나리오
#   run_db_query("resource supply")     # 이름으로 실행
#   export_all_from_db()                # 전체 export (전체 시나리오)
#   export_all_from_db(c("S1","S08"))   # 특정 시나리오만 export
#   load_exported()                     # 저장된 RDS 로드
#
# PREREQUISITES:
#   - kaist/config.R 설정 완료 (db_path, db_name 등)
#   - GCAM BaseX DB 접근 가능
#   - Java 설치 (BaseX 실행에 필요)
#   - rgcam 패키지 설치 (ModelInterface JAR 경로 참조용)
#
################################################################################

########## Libraries ##########
library(dplyr)
library(readr)
library(here)
library(xml2)
###############################

########## Load Configuration ##########
source(file.path(here(), "kaist/config.R"))
########################################

###############################################################################
#                          BaseX Engine (self-contained)
#
#  rgcam_patch.R를 source하지 않고, BaseX 9.5+ 호환 명령을 직접 구현.
#  rgcam 패키지에서 ModelInterface classpath만 참조.
###############################################################################

# ModelInterface classpath (rgcam 번들에서 가져옴)
.mi_classpath <- rgcam:::DEFAULT.MICLASSPATH()
.max_memory <- "4g"

#' BaseX XQuery 실행 (9.5+ 호환: "OPEN DB; RUN file" 방식)
#'
#' @param xquery_string XQuery 문자열
#' @param csv_format CSV 포맷 옵션 (NULL 또는 "xquery")
#' @return data.frame (CSV 파싱 결과)
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

  system2("java", args = paste(cmd_args, collapse = " "))
  read_csv(tmp_output_fn, col_types = cols(), show_col_types = FALSE)
}

#' ModelInterface mi:runMIQuery 실행
#'
#' @param query_xml 쿼리 XML 문자열 (예: <supplyDemandQuery ...>)
#' @param scenarios 시나리오 이름 벡터
#' @param regions region 이름 벡터 (NULL = 전체)
#' @return data.frame (후처리 완료)
run_mi_query <- function(query_xml, scenarios, regions = NULL) {
  xqScenarios <- paste0("('", paste(scenarios, collapse = "','"), "')")
  xqRegion <- if (is.null(regions)) "()" else
    paste0("('", paste(regions, collapse = "','"), "')")

  query_xml <- gsub("\n", "", query_xml)
  query_xml <- gsub("\\s+", " ", query_xml)

  xquery <- paste0(
    "import module namespace mi = 'ModelInterface.ModelGUI2.xmldb.RunMIQuery';",
    "mi:runMIQuery(", query_xml, ",", xqScenarios, ",", xqRegion, ")"
  )

  raw <- run_basex(xquery, csv_format = "xquery")
  post_process_query(raw)
}

###############################################################################
#                          Post-processing
#
#  rgcam:::miquery_post + table.cleanup 재현
#  (group_by + sum → stdcase → sep.date)
###############################################################################

#' 쿼리 결과 후처리
#'
#' BaseX CSV → (1) 중복 행 합산 → (2) 컬럼명 정리 → (3) scenario+date 분리
post_process_query <- function(results) {
  if (is.null(results) || nrow(results) == 0) return(tibble::tibble())

  # 1. Sum duplicate rows (miquery_post)
  #    value 컬럼이 있으면 나머지 컬럼 기준으로 group_by + sum
  val_idx <- which(tolower(names(results)) == "value")
  if (length(val_idx) > 0) {
    names(results)[val_idx[1]] <- "value"
    results <- results %>%
      group_by(across(-value)) %>%
      summarize(value = sum(value, na.rm = TRUE), .groups = "drop")
  }

  # 2. Lowercase non-year, non-Units columns (stdcase)
  is_year <- grepl("^X[0-9]{4}", names(results))
  is_units <- grepl("^units$", names(results), ignore.case = TRUE)
  to_lower <- !is_year & !is_units
  names(results)[to_lower] <- tolower(names(results)[to_lower])
  names(results)[is_units] <- "Units"

  # 3. Split "S1,date=..." → scenario + rundate (table.scen.trim + sep.date)
  if ("scenario" %in% names(results)) {
    parts <- stringr::str_split_fixed(results$scenario, ",date=", 2)
    results$scenario <- parts[, 1]
    results$rundate <- as.POSIXct(NA)
    has_date <- parts[, 2] != ""
    if (any(has_date)) {
      results$rundate[has_date] <- lubridate::ydm_hms(parts[has_date, 2])
    }
  }

  results
}

#' 쿼리 결과에서 중복 시나리오 제거 (최신 rundate만 유지)
dedup_scenarios <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  if (!"rundate" %in% names(df) || !"scenario" %in% names(df)) return(df)

  latest <- df %>%
    filter(!is.na(rundate)) %>%
    group_by(scenario) %>%
    summarize(latest_date = max(rundate, na.rm = TRUE), .groups = "drop")

  if (nrow(latest) == 0) return(df)

  df %>%
    left_join(latest, by = "scenario") %>%
    filter(is.na(rundate) | rundate == latest_date) %>%
    select(-latest_date)
}

###############################################################################
#                          Helpers
###############################################################################

sanitize_name <- function(x) {
  x <- gsub("[^a-zA-Z0-9_]", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  substr(x, 1, 100)
}

###############################################################################
#                     Parse Main_queries.xml
###############################################################################

main_queries_path <- file.path(here(), "gcam_input/output/queries/Main_queries.xml")
if (!file.exists(main_queries_path)) {
  stop("Main_queries.xml not found at: ", main_queries_path)
}

.mq_xml <- read_xml(main_queries_path)
.mq_nodes <- xml_find_all(.mq_xml, paste0(
  "//*[self::supplyDemandQuery or self::emissionsQueryBuilder or ",
  "self::demographicsQuery or self::gdpQueryBuilder or ",
  "self::query or self::singleQuery][@title]"
))
.mq_titles <- xml_attr(.mq_nodes, "title")

.mq_groups <- sapply(.mq_nodes, function(node) {
  ancestors <- xml_find_all(node, "ancestor::queryGroup")
  paste(xml_attr(ancestors, "name"), collapse = " > ")
})

###############################################################################
#                          Functions
###############################################################################

#' DB의 시나리오 목록 조회 (중복 이름은 최신만 유지)
#'
#' @return data.frame (name, date 컬럼)
list_scenarios <- function() {
  xquery <- paste0(
    'let $scns := collection()/scenario ',
    'return document{ element csv { ',
    'for $scn in $scns return element record { ',
    'element name { text { $scn/@name } }, ',
    'element date { text { $scn/@date } } } } }'
  )
  result <- run_basex(xquery)

  if (nrow(result) == 0) {
    cat("No scenarios found in database.\n")
    return(result)
  }

  dupes <- duplicated(result$name, fromLast = TRUE)
  if (any(dupes)) {
    dup_names <- unique(result$name[dupes])
    cat("Note: duplicate scenario names:", paste(dup_names, collapse = ", "), "\n")
    cat("  Keeping latest version for each.\n")
  }
  result <- result[!dupes, ]

  cat("Scenarios (", nrow(result), "):", paste(result$name, collapse = ", "), "\n")
  result
}

#' Main_queries.xml의 전체 쿼리 목록 출력
#'
#' @param pattern 이름 필터 정규식 (예: "elec", "CO2")
list_all_queries <- function(pattern = NULL) {
  titles <- .mq_titles
  groups <- .mq_groups
  idx <- seq_along(titles)

  if (!is.null(pattern)) {
    matches <- grep(pattern, titles, ignore.case = TRUE)
    if (length(matches) == 0) {
      cat("No queries matching '", pattern, "'\n")
      return(invisible(character(0)))
    }
    idx <- matches
  }

  width <- nchar(length(.mq_titles))
  for (i in idx) {
    cat(sprintf("[%0*d] %s  (%s)\n", width, i, titles[i], groups[i]))
  }
  cat("\n  Total:", length(idx), "queries shown\n")
  invisible(titles[idx])
}

#' DB에서 직접 쿼리 실행
#'
#' @param n 쿼리 번호(numeric) 또는 이름/부분매칭(character)
#' @param scenarios 시나리오 이름 벡터 (NULL = 전체 시나리오 자동 감지)
#' @param region 필터링할 region (NULL = 전체)
#' @return tibble
run_db_query <- function(n, scenarios = NULL, region = target_region) {
  titles <- .mq_titles

  if (is.numeric(n)) {
    if (n < 1 || n > length(titles)) {
      stop("Query number out of range. Valid: 1-", length(titles))
    }
    idx <- n
  } else if (is.character(n)) {
    matches <- grep(n, titles, ignore.case = TRUE)
    if (length(matches) == 0) {
      stop("No query matching '", n, "'. Run list_all_queries() to see all.")
    }
    if (length(matches) > 1) {
      cat("Multiple matches:\n")
      for (m in matches) cat(sprintf("  [%d] %s\n", m, titles[m]))
      cat("Using first match: [", matches[1], "]\n\n")
    }
    idx <- matches[1]
  } else {
    stop("n must be numeric or character")
  }

  query_title <- titles[idx]
  query_xml <- as.character(.mq_nodes[[idx]])

  # 시나리오 자동 감지
  if (is.null(scenarios)) {
    scen_info <- list_scenarios()
    scenarios <- scen_info$name
  }

  cat("Running query [", idx, "]:", query_title, "\n")
  cat("Category:", .mq_groups[idx], "\n")
  cat("Scenarios:", paste(scenarios, collapse = ", "), "\n")

  query_regions <- if (!is.null(region)) region else NULL

  result <- tryCatch(
    run_mi_query(query_xml, scenarios, query_regions),
    error = function(e) {
      cat("ERROR:", e$message, "\n")
      return(NULL)
    }
  )

  if (is.null(result) || nrow(result) == 0) {
    cat("No results returned.\n")
    return(invisible(tibble::tibble()))
  }

  # 중복 시나리오 제거 (최신 rundate만)
  result <- dedup_scenarios(result)

  # 추가 region 필터링
  if (!is.null(region) && "region" %in% names(result)) {
    result <- result %>% filter(region == !!region)
  }

  cat("Rows:  ", nrow(result), "\n")
  cat("Cols:  ", paste(names(result), collapse = ", "), "\n\n")
  result
}

#' 전체 쿼리를 DB에서 실행하여 CSV + RDS 저장
#'
#' @param scenarios 시나리오 이름 벡터 (NULL = 전체 시나리오 자동 감지)
#' @param region 필터링할 region (NULL = 전체)
#' @param output_path 출력 디렉토리
export_all_from_db <- function(scenarios = NULL, region = target_region,
                               output_path = output_dir) {
  titles <- .mq_titles
  export_dir <- file.path(output_path, "query_export_full")
  if (!dir.exists(export_dir)) dir.create(export_dir, recursive = TRUE)

  # 시나리오 자동 감지
  if (is.null(scenarios)) {
    scen_info <- list_scenarios()
    scenarios <- scen_info$name
  }
  query_regions <- if (!is.null(region)) region else NULL

  all_data <- list()
  index <- data.frame(
    number = integer(), query_name = character(), group = character(),
    n_rows = integer(), n_scenarios = integer(), columns = character(),
    stringsAsFactors = FALSE
  )

  cat("\nScenarios:", paste(scenarios, collapse = ", "), "\n")
  cat("Exporting", length(titles), "queries",
      if (!is.null(region)) paste0("(region: ", region, ")") else "(all regions)",
      "\n\n")

  for (i in seq_along(titles)) {
    qname <- titles[i]
    cat(sprintf("[%03d/%03d] %s ... ", i, length(titles), qname))

    query_xml <- as.character(.mq_nodes[[i]])

    result <- tryCatch(
      run_mi_query(query_xml, scenarios, query_regions),
      error = function(e) {
        cat("ERROR:", e$message, "\n")
        return(NULL)
      }
    )

    # 중복 시나리오 제거
    result <- dedup_scenarios(result)

    if (is.null(result) || nrow(result) == 0) {
      cat("0 rows\n")
      next
    }

    # region 필터링
    if (!is.null(region) && "region" %in% names(result)) {
      result <- result %>% filter(region == !!region)
    }

    if (nrow(result) == 0) {
      cat("0 rows after filter\n")
      next
    }

    n_scen <- if ("scenario" %in% names(result)) length(unique(result$scenario)) else NA

    all_data[[qname]] <- result

    index <- rbind(index, data.frame(
      number = i, query_name = qname, group = .mq_groups[i],
      n_rows = nrow(result), n_scenarios = n_scen,
      columns = paste(names(result), collapse = "; "),
      stringsAsFactors = FALSE
    ))

    csv_path <- file.path(export_dir, paste0(
      sprintf("%03d", i), "_", sanitize_name(qname), ".csv"
    ))
    write.csv(result, csv_path, row.names = FALSE)

    scen_str <- if (!is.na(n_scen)) paste0(n_scen, " scen") else ""
    cat(nrow(result), "rows (", scen_str, ")\n")
  }

  # RDS 저장
  region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
  rds_path <- file.path(export_dir, paste0("all_queries_full_", region_tag, ".rds"))
  saveRDS(all_data, rds_path)
  cat("\nRDS saved:", rds_path, "\n")

  # Index 저장
  index_path <- file.path(export_dir, "query_index_full.csv")
  write.csv(index, index_path, row.names = FALSE)
  cat("Index saved:", index_path, "\n")

  # 시나리오 커버리지 요약
  if ("n_scenarios" %in% names(index) && nrow(index) > 0) {
    full_cov <- sum(index$n_scenarios == length(scenarios), na.rm = TRUE)
    cat("\nScenario coverage: ", full_cov, "/", nrow(index), " queries have all ",
        length(scenarios), " scenarios\n", sep = "")
  }

  cat("Done! Exported", length(all_data), "/", length(titles),
      "queries to", export_dir, "\n")
  invisible(all_data)
}

#' 저장된 RDS 캐시 로드
#'
#' @param region region 태그 (NULL = "all_regions")
#' @param output_path 출력 디렉토리
load_exported <- function(region = target_region, output_path = output_dir) {
  region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
  rds_path <- file.path(output_path, "query_export_full",
                        paste0("all_queries_full_", region_tag, ".rds"))
  if (!file.exists(rds_path)) {
    stop("No exported data at: ", rds_path, "\nRun export_all_from_db() first.")
  }
  cat("Loading:", rds_path, "\n")
  data <- readRDS(rds_path)
  cat("Loaded", length(data), "queries\n")
  data
}

###############################################################################
#                          Startup
###############################################################################

cat("\n============================================\n")
cat("  GCAM Query Browser (Without .dat)\n")
cat("============================================\n")
cat("Database:      ", db_name, "at", db_path, "\n")
cat("Main_queries:  ", length(.mq_titles), "queries (from XML)\n")
cat("============================================\n\n")

cat("--- Usage ---\n")
cat("  list_scenarios()                    # DB scenarios (deduped)\n")
cat("  list_all_queries()                  # List all 335 queries\n")
cat("  list_all_queries(\"elec\")            # Filter by name\n")
cat("  run_db_query(10)                    # Run query #10 (all scenarios)\n")
cat("  run_db_query(10, c(\"S1\",\"S08\"))     # Run with specific scenarios\n")
cat("  run_db_query(\"resource supply\")     # Run by name\n")
cat("  export_all_from_db()                # Export ALL (all scenarios)\n")
cat("  export_all_from_db(c(\"S1\",\"S08\"))   # Export specific scenarios\n")
cat("  load_exported()                     # Load saved RDS\n")
cat("-------------\n\n")
