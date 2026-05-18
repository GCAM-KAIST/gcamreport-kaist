################################################################################
# GCAM Query Browser
#
# PURPOSE:
#   .dat 프로젝트 파일에서 모든 GCAM 쿼리 결과를 번호로 빠르게 조회하고,
#   특정 region(기본: South Korea)의 전체 쿼리 결과를 CSV/RDS로 일괄 저장.
#
# USAGE:
#   source("kaist/query_browser.R")   # 자동으로 쿼리 목록 출력
#
#   list_queries()              # 번호 매긴 전체 쿼리 목록
#   get_query(5)                # 5번 쿼리 (South Korea)
#   get_query(5, region = NULL) # 5번 쿼리 (전체 region)
#   get_query("elec gen")       # 이름 부분 매칭
#   export_all()                # 전체 쿼리 CSV + RDS 저장
#
#   # 이후 세션 (rgcam 불필요):
#   cached <- load_cached()
#   cached[["elec gen by gen tech"]]
#
# PREREQUISITES:
#   - kaist/config.R 설정 완료
#   - .dat 프로젝트 파일 존재 (step1에서 생성)
#
################################################################################

########## Libraries ##########
library(rgcam)
library(dplyr)
library(here)
###############################

########## Load Configuration ##########
source(file.path(here(), "kaist/config.R"))
########################################

########## Load Project File ##########
# project_dir and output_dir are absolute paths from config.R
# Search both project_dir and output_dir for .dat files
prj_files <- c(
  list.files(project_dir, pattern = ".*project_.*\\.dat$", full.names = TRUE),
  list.files(output_dir,  pattern = ".*project_.*\\.dat$", full.names = TRUE)
)
prj_files <- unique(prj_files)

if (length(prj_files) == 0) {
  stop("No .dat project file found in:\n  ", project_dir, "\n  ", output_dir,
       "\nRun step1_generate_report.R first.")
}

prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
prj <- loadProject(prj_file)

.qb_scenarios <- listScenarios(prj)
.qb_queries <- listQueries(prj)

cat("\n========================================\n")
cat("  GCAM Query Browser\n")
cat("========================================\n")
cat("Project file:", basename(prj_file), "\n")
cat("Scenarios:   ", length(.qb_scenarios), "-",
    paste(.qb_scenarios, collapse = ", "), "\n")
cat("Queries:     ", length(.qb_queries), "\n")
cat("========================================\n\n")
#######################################

########## Helper ##########
sanitize_name <- function(x) {
  x <- gsub("[^a-zA-Z0-9_]", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  substr(x, 1, 100)
}
############################

########## Functions ##########

#' 번호 매긴 쿼리 목록 출력
#'
#' @param .prj rgcam project object (default: prj)
#' @return character vector of query names (invisible)
list_queries <- function(.prj = prj) {
  queries <- listQueries(.prj)
  width <- nchar(length(queries))
  for (i in seq_along(queries)) {
    cat(sprintf("[%0*d] %s\n", width, i, queries[i]))
  }
  invisible(queries)
}

#' 번호 또는 이름으로 쿼리 결과 조회
#'
#' @param n 쿼리 번호(numeric) 또는 이름/부분매칭 문자열(character)
#' @param region 필터링할 region (NULL = 전체, default: target_region)
#' @param scenario 필터링할 scenario (NULL = 전체)
#' @param .prj rgcam project object (default: prj)
#' @return tibble
get_query <- function(n, region = target_region, scenario = NULL, .prj = prj) {
  queries <- listQueries(.prj)

  if (is.numeric(n)) {
    if (n < 1 || n > length(queries)) {
      stop("Query number out of range. Valid: 1-", length(queries))
    }
    query_name <- queries[n]
  } else if (is.character(n)) {
    matches <- grep(n, queries, ignore.case = TRUE)
    if (length(matches) == 0) {
      stop("No query matching '", n, "'. Run list_queries() to see all.")
    }
    if (length(matches) > 1) {
      cat("Multiple matches found:\n")
      for (m in matches) {
        cat(sprintf("  [%d] %s\n", m, queries[m]))
      }
      cat("Using first match: [", matches[1], "] ", queries[matches[1]], "\n\n")
    }
    query_name <- queries[matches[1]]
  } else {
    stop("n must be numeric (query number) or character (query name/pattern)")
  }

  result <- tryCatch(
    getQuery(.prj, query_name),
    error = function(e) {
      stop("Failed to get query '", query_name, "': ", e$message)
    }
  )

  if (!is.null(region) && "region" %in% names(result)) {
    result <- result %>% filter(region == !!region)
  }
  if (!is.null(scenario) && "scenario" %in% names(result)) {
    result <- result %>% filter(scenario == !!scenario)
  }

  cat("Query: ", query_name, "\n")
  cat("Rows:  ", nrow(result), "\n")
  cat("Cols:  ", paste(names(result), collapse = ", "), "\n")
  if (!is.null(region)) cat("Region:", region, "\n")
  cat("\n")

  result
}

#' 전체 쿼리를 CSV + RDS로 일괄 저장
#'
#' @param region 필터링할 region (NULL = 전체, default: target_region)
#' @param format "both", "csv", "rds"
#' @param output_path 출력 디렉토리 (default: output_dir)
#' @param .prj rgcam project object (default: prj)
export_all <- function(region = target_region, format = "both",
                       output_path = output_dir, .prj = prj) {
  queries <- listQueries(.prj)
  export_dir <- file.path(output_path, "query_export")
  if (!dir.exists(export_dir)) dir.create(export_dir, recursive = TRUE)

  all_data <- list()
  index <- data.frame(
    number = integer(),
    query_name = character(),
    n_rows = integer(),
    columns = character(),
    stringsAsFactors = FALSE
  )

  cat("Exporting", length(queries), "queries",
      if (!is.null(region)) paste0("(region: ", region, ")") else "(all regions)",
      "\n\n")

  for (i in seq_along(queries)) {
    qname <- queries[i]
    cat(sprintf("[%02d/%02d] %s ... ", i, length(queries), qname))

    result <- tryCatch(
      getQuery(.prj, qname),
      error = function(e) {
        cat("ERROR:", e$message, "\n")
        return(NULL)
      }
    )

    if (is.null(result)) next

    if (!is.null(region) && "region" %in% names(result)) {
      result <- result %>% filter(region == !!region)
    }

    all_data[[qname]] <- result

    index <- rbind(index, data.frame(
      number = i,
      query_name = qname,
      n_rows = nrow(result),
      columns = paste(names(result), collapse = "; "),
      stringsAsFactors = FALSE
    ))

    if (format %in% c("csv", "both")) {
      csv_path <- file.path(export_dir, paste0(
        sprintf("%02d", i), "_", sanitize_name(qname), ".csv"
      ))
      write.csv(result, csv_path, row.names = FALSE)
    }

    cat(nrow(result), "rows\n")
  }

  if (format %in% c("rds", "both")) {
    region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
    rds_path <- file.path(export_dir, paste0("all_queries_", region_tag, ".rds"))
    saveRDS(all_data, rds_path)
    cat("\nRDS saved:", rds_path, "\n")
  }

  index_path <- file.path(export_dir, "query_index.csv")
  write.csv(index, index_path, row.names = FALSE)
  cat("Index saved:", index_path, "\n")
  cat("\nDone! Exported", length(all_data), "queries to", export_dir, "\n")

  invisible(all_data)
}

#' RDS 캐시에서 바로 로드 (rgcam 불필요)
#'
#' @param region region 이름 (default: target_region)
#' @param output_path 출력 디렉토리 (default: output_dir)
#' @return named list of tibbles
load_cached <- function(region = target_region, output_path = output_dir) {
  region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
  rds_path <- file.path(output_path, "query_export",
                        paste0("all_queries_", region_tag, ".rds"))
  if (!file.exists(rds_path)) {
    stop("No cached data found at: ", rds_path,
         "\nRun export_all() first to create the cache.")
  }
  cat("Loading cached data from:", rds_path, "\n")
  data <- readRDS(rds_path)
  cat("Loaded", length(data), "queries\n")
  data
}

################################

########## Auto-run ##########
list_queries()

cat("\n--- Usage ---\n")
cat("  list_queries()              # Show all queries\n")
cat("  get_query(5)                # Get query #5 (South Korea)\n")
cat("  get_query(5, region = NULL) # Get query #5 (all regions)\n")
cat("  get_query(\"elec gen\")       # Partial name match\n")
cat("  export_all()                # Export all to CSV + RDS\n")
cat("  load_cached()               # Load from RDS (no rgcam needed)\n")
cat("-------------\n\n")
##############################
