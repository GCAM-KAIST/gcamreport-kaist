################################################################################
# GCAM Query Browser (Full Edition)
#
# PURPOSE:
#   query_browser.R의 확장 버전.
#   .dat 캐시에 있는 76개 쿼리 + Main_queries.xml의 335개 전체 쿼리에 접근.
#   .dat에 없는 쿼리는 BaseX DB에 직접 실행하여 결과를 가져옴.
#
# USAGE:
#   source("kaist/query_browser_full.R")
#
#   # === .dat 캐시 쿼리 (기존 기능) ===
#   list_queries()              # .dat에 있는 쿼리 목록
#   get_query(5)                # .dat에서 5번 쿼리 조회
#
#   # === Main_queries.xml 전체 쿼리 (새 기능) ===
#   list_all_queries()          # 335개 전체 쿼리 목록
#   run_db_query(10)            # DB에서 직접 10번 쿼리 실행
#   run_db_query("resource supply curves")  # 이름으로 실행
#   export_all_from_db()              # 335개 전체를 DB에서 실행 후 저장 (전체 시나리오)
#   export_all_from_db(c("S1","S08")) # 특정 시나리오만 export
#
# PREREQUISITES:
#   - kaist/config.R 설정 완료
#   - .dat 프로젝트 파일 존재 (step1에서 생성)
#   - GCAM BaseX DB 접근 가능 (DB에서 직접 쿼리 시)
#
################################################################################

########## Libraries ##########
library(rgcam)
library(dplyr)
library(here)
library(xml2)
###############################

export_all_from_db(c("S1","S08", "05_nzL1b_Adv_plus")) 

########## Load Configuration ##########
source(file.path(here(), "kaist/config.R"))

# Apply rgcam patch for BaseX 9.5+ compatibility
source(file.path(here(), "kaist/rgcam_patch.R"))
########################################

########## Load Project File (.dat cache) ##########
prj_files <- c(
  list.files(project_dir, pattern = ".*project_.*\\.dat$", full.names = TRUE),
  list.files(output_dir,  pattern = ".*project_.*\\.dat$", full.names = TRUE)
)
prj_files <- unique(prj_files)

if (length(prj_files) == 0) {
  warning("No .dat project file found. Cached query functions will not work.")
  prj <- NULL
} else {
  prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
  prj <- loadProject(prj_file)
  cat("Loaded .dat cache:", basename(prj_file), "\n")
}
####################################################

########## Parse Main_queries.xml ##########
# Main_queries.xml 경로 (ModelInterface가 사용하는 전체 쿼리 파일)
main_queries_path <- file.path(here(), "gcam_input/output/queries/Main_queries.xml")

if (!file.exists(main_queries_path)) {
  stop("Main_queries.xml not found at: ", main_queries_path)
}

# xml2로 파싱 - 모든 쿼리 엘리먼트 추출
.mq_xml <- read_xml(main_queries_path)
.mq_nodes <- xml_find_all(.mq_xml, paste0(
  "//*[self::supplyDemandQuery or self::emissionsQueryBuilder or ",
  "self::demographicsQuery or self::gdpQueryBuilder or ",
  "self::query or self::singleQuery][@title]"
))
.mq_titles <- xml_attr(.mq_nodes, "title")

# queryGroup 경로 추출 (카테고리 정보)
.mq_groups <- sapply(.mq_nodes, function(node) {
  ancestors <- xml_find_all(node, "ancestor::queryGroup")
  paste(xml_attr(ancestors, "name"), collapse = " > ")
})
############################################

########## DB Connection (lazy) ##########
# DB 연결은 필요할 때만 생성
.db_conn <- NULL

get_db_conn <- function() {
  if (is.null(.db_conn)) {
    cat("Connecting to BaseX database:", db_name, "at", db_path, "\n")
    .db_conn <<- localDBConn(db_path, db_name)
  }
  .db_conn
}
##########################################

########## Helpers ##########
sanitize_name <- function(x) {
  x <- gsub("[^a-zA-Z0-9_]", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  substr(x, 1, 100)
}

#' DB에서 시나리오 목록 가져오기 (중복 이름은 최신만 유지)
#'
#' listScenariosInDB()에서 같은 이름의 시나리오가 여러 개인 경우,
#' 나중에 저장된 (마지막) 항목만 유지합니다.
#'
#' @param conn DB 연결 객체
#' @return 중복 제거된 시나리오 이름 벡터
get_db_scenarios <- function(conn) {
  scen_info <- rgcam::listScenariosInDB(conn)
  dupes <- duplicated(scen_info$name, fromLast = TRUE)
  if (any(dupes)) {
    dup_names <- unique(scen_info$name[dupes])
    cat("Note: duplicate scenario names detected:", paste(dup_names, collapse = ", "), "\n")
    cat("  Keeping latest version for each.\n")
  }
  scen_info <- scen_info[!dupes, ]
  scen_info$name
}

#' 쿼리 결과에서 중복 시나리오 제거 (최신 rundate만 유지)
#'
#' runQuery() 결과에 같은 이름의 시나리오가 여러 개 포함된 경우,
#' rundate가 가장 최근인 데이터만 유지합니다.
#'
#' @param df runQuery() 결과 data.frame
#' @return 중복 제거된 data.frame
dedup_scenarios <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  if (!"rundate" %in% names(df) || !"scenario" %in% names(df)) return(df)

  # 각 시나리오별 최신 rundate
  latest <- df %>%
    filter(!is.na(rundate)) %>%
    group_by(scenario) %>%
    summarize(latest_date = max(rundate, na.rm = TRUE), .groups = "drop")

  if (nrow(latest) == 0) return(df)

  # rundate가 있는 행: 최신만 유지 / rundate가 NA인 행: 그대로 유지
  df %>%
    left_join(latest, by = "scenario") %>%
    filter(is.na(rundate) | rundate == latest_date) %>%
    select(-latest_date)
}
#############################

########## Summary ##########
.qb_cached_queries <- if (!is.null(prj)) listQueries(prj) else character(0)
.qb_scenarios <- if (!is.null(prj)) listScenarios(prj) else character(0)

cat("\n============================================\n")
cat("  GCAM Query Browser (Full Edition)\n")
cat("============================================\n")
if (!is.null(prj)) {
  cat("Cached (.dat): ", length(.qb_cached_queries), "queries\n")
  cat("Scenarios:     ", paste(.qb_scenarios, collapse = ", "), "\n")
}
cat("Main_queries:  ", length(.mq_titles), "queries (from XML)\n")
cat("Database:      ", db_name, "at", db_path, "\n")
cat("============================================\n\n")
#############################

########## Functions: Cached (.dat) ##########

#' .dat에 캐시된 쿼리 목록 출력
list_queries <- function(.prj = prj) {
  if (is.null(.prj)) {
    cat("No .dat file loaded.\n")
    return(invisible(character(0)))
  }
  queries <- listQueries(.prj)
  width <- nchar(length(queries))
  for (i in seq_along(queries)) {
    cat(sprintf("[%0*d] %s\n", width, i, queries[i]))
  }
  invisible(queries)
}

#' .dat 캐시에서 쿼리 결과 조회 (번호 또는 이름)
get_query <- function(n, region = target_region, scenario = NULL, .prj = prj) {
  if (is.null(.prj)) stop("No .dat file loaded.")
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
      for (m in matches) cat(sprintf("  [%d] %s\n", m, queries[m]))
      cat("Using first match: [", matches[1], "] ", queries[matches[1]], "\n\n")
    }
    query_name <- queries[matches[1]]
  } else {
    stop("n must be numeric or character")
  }

  result <- tryCatch(
    getQuery(.prj, query_name),
    error = function(e) stop("Failed: ", e$message)
  )

  if (!is.null(region) && "region" %in% names(result))
    result <- result %>% filter(region == !!region)
  if (!is.null(scenario) && "scenario" %in% names(result))
    result <- result %>% filter(scenario == !!scenario)

  cat("Query: ", query_name, "\n")
  cat("Rows:  ", nrow(result), " | Region:", ifelse(is.null(region), "All", region), "\n\n")
  result
}

##############################################

########## Functions: Full DB Queries ##########

#' Main_queries.xml의 전체 335개 쿼리 목록 출력
#'
#' @param pattern 선택: 이름 필터 정규식 (예: "elec", "CO2")
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
    # .dat에 캐시되어 있으면 [*] 표시
    cached <- if (titles[i] %in% .qb_cached_queries) "*" else " "
    cat(sprintf("[%0*d]%s %s  (%s)\n", width, i, cached, titles[i], groups[i]))
  }

  cat("\n  * = cached in .dat (use get_query()),  no * = use run_db_query()\n")
  cat("  Total:", length(idx), "queries shown\n")
  invisible(titles[idx])
}

#' DB에서 직접 쿼리 실행 (Main_queries.xml의 아무 쿼리나)
#'
#' @param n 쿼리 번호(numeric) 또는 이름/부분매칭(character)
#' @param scenarios 시나리오 필터 (NULL = DB의 전체 시나리오 자동 감지)
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
  query_xml_string <- as.character(.mq_nodes[[idx]])

  # 시나리오 자동 감지 (중복 이름은 최신만 유지)
  if (is.null(scenarios)) {
    conn <- get_db_conn()
    scenarios <- get_db_scenarios(conn)
    cat("Detected scenarios:", paste(scenarios, collapse = ", "), "\n")
  }

  cat("Running query [", idx, "]:", query_title, "\n")
  cat("Category:", .mq_groups[idx], "\n")

  # 먼저 .dat 캐시에 있는지 확인
  if (!is.null(prj) && query_title %in% .qb_cached_queries) {
    result <- tryCatch(getQuery(prj, query_title), error = function(e) NULL)
    # 캐시에 요청한 시나리오가 모두 있는지 확인
    if (!is.null(result) && "scenario" %in% names(result)) {
      cached_scens <- unique(result$scenario)
      if (all(scenarios %in% cached_scens)) {
        cat("(Found in .dat cache - all scenarios present)\n")
        result <- result %>% filter(scenario %in% scenarios)
      } else {
        missing <- setdiff(scenarios, cached_scens)
        cat("(Cache incomplete, missing:", paste(missing, collapse = ", "),
            "- querying DB)\n")
        result <- NULL
      }
    } else if (!is.null(result)) {
      cat("(Found in .dat cache)\n")
    }
  } else {
    result <- NULL
  }

  # 캐시에 없거나 불완전하면 DB에서 직접 실행
  if (is.null(result)) {
    cat("(Executing against BaseX database...)\n")
    conn <- get_db_conn()
    query_regions <- if (!is.null(region)) region else NULL

    result <- tryCatch(
      rgcam::runQuery(conn, query_xml_string, scenarios, query_regions,
                      warn.empty = FALSE),
      error = function(e) {
        cat("ERROR:", e$message, "\n")
        return(NULL)
      }
    )

    if (is.null(result) || nrow(result) == 0) {
      cat("No results returned.\n")
      return(invisible(tibble::tibble()))
    }

    # DB 결과에서 중복 시나리오 제거 (최신 rundate만 유지)
    result <- dedup_scenarios(result)
  }

  # 추가 region 필터링 (캐시에서 가져온 경우)
  if (!is.null(region) && "region" %in% names(result)) {
    result <- result %>% filter(region == !!region)
  }

  cat("Rows:  ", nrow(result), "\n")
  cat("Cols:  ", paste(names(result), collapse = ", "), "\n\n")
  result
}

#' 전체 쿼리를 DB에서 실행하여 CSV + RDS 저장
#'
#' @param scenarios 시나리오 필터 (NULL = DB의 전체 시나리오 자동 감지)
#'   예: c("S1", "S08") 또는 NULL
#' @param region 필터링할 region (NULL = 전체)
#' @param output_path 출력 디렉토리
#' @param use_cache TRUE면 .dat에 있는 쿼리는 캐시에서 가져옴 (단, 모든 시나리오가 있을 때만)
export_all_from_db <- function(scenarios = NULL, region = target_region,
                               output_path = output_dir, use_cache = TRUE) {
  titles <- .mq_titles
  export_dir <- file.path(output_path, "query_export_full")
  if (!dir.exists(export_dir)) dir.create(export_dir, recursive = TRUE)

  conn <- get_db_conn()

  # 시나리오 자동 감지 (중복 이름은 최신만 유지)
  if (is.null(scenarios)) {
    scenarios <- get_db_scenarios(conn)
  }
  query_regions <- if (!is.null(region)) region else NULL

  all_data <- list()
  index <- data.frame(
    number = integer(), query_name = character(), group = character(),
    n_rows = integer(), n_scenarios = integer(), source = character(),
    columns = character(),
    stringsAsFactors = FALSE
  )

  cat("Scenarios:", paste(scenarios, collapse = ", "), "\n")
  cat("Exporting", length(titles), "queries",
      if (!is.null(region)) paste0("(region: ", region, ")") else "(all regions)",
      "\n\n")

  for (i in seq_along(titles)) {
    qname <- titles[i]
    cat(sprintf("[%03d/%03d] %s ... ", i, length(titles), qname))

    result <- NULL
    src <- "db"

    # .dat 캐시 확인 (요청한 시나리오가 모두 있을 때만 사용)
    if (use_cache && !is.null(prj) && qname %in% .qb_cached_queries) {
      cached_result <- tryCatch(getQuery(prj, qname), error = function(e) NULL)
      if (!is.null(cached_result) && "scenario" %in% names(cached_result)) {
        cached_scens <- unique(cached_result$scenario)
        if (all(scenarios %in% cached_scens)) {
          result <- cached_result %>% filter(scenario %in% scenarios)
          src <- "cache"
        }
        # 시나리오 불완전하면 result = NULL → DB 폴백
      } else if (!is.null(cached_result)) {
        # scenario 컬럼이 없는 쿼리 (예: demographics) → 그대로 사용
        result <- cached_result
        src <- "cache"
      }
    }

    # 캐시에 없거나 불완전하면 DB에서 실행 (명시적 시나리오 전달)
    if (is.null(result)) {
      query_xml_string <- as.character(.mq_nodes[[i]])
      result <- tryCatch(
        rgcam::runQuery(conn, query_xml_string, scenarios, query_regions,
                        warn.empty = FALSE),
        error = function(e) {
          cat("ERROR:", e$message, "\n")
          return(NULL)
        }
      )
      # DB 결과에서 중복 시나리오 제거 (최신 rundate만 유지)
      result <- dedup_scenarios(result)
    }

    if (is.null(result) || nrow(result) == 0) {
      cat("0 rows (", src, ")\n")
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

    # 시나리오 수 확인
    n_scen <- if ("scenario" %in% names(result)) length(unique(result$scenario)) else NA

    all_data[[qname]] <- result

    index <- rbind(index, data.frame(
      number = i, query_name = qname, group = .mq_groups[i],
      n_rows = nrow(result), n_scenarios = n_scen, source = src,
      columns = paste(names(result), collapse = "; "),
      stringsAsFactors = FALSE
    ))

    csv_path <- file.path(export_dir, paste0(
      sprintf("%03d", i), "_", sanitize_name(qname), ".csv"
    ))
    write.csv(result, csv_path, row.names = FALSE)

    scen_info_str <- if (!is.na(n_scen)) paste0(n_scen, " scen") else ""
    cat(nrow(result), "rows (", src, ",", scen_info_str, ")\n")
  }

  # RDS 저장
  region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
  scen_tag <- paste(scenarios, collapse = "_")
  rds_path <- file.path(export_dir, paste0("all_queries_full_", region_tag, ".rds"))
  saveRDS(all_data, rds_path)
  cat("\nRDS saved:", rds_path, "\n")

  # Index 저장
  index_path <- file.path(export_dir, "query_index_full.csv")
  write.csv(index, index_path, row.names = FALSE)
  cat("Index saved:", index_path, "\n")

  # 시나리오 커버리지 요약
  if ("n_scenarios" %in% names(index)) {
    full_cov <- sum(index$n_scenarios == length(scenarios), na.rm = TRUE)
    partial_cov <- sum(index$n_scenarios < length(scenarios) & index$n_scenarios > 0, na.rm = TRUE)
    cat("\nScenario coverage: ", full_cov, "/", nrow(index), " queries have all ",
        length(scenarios), " scenarios", sep = "")
    if (partial_cov > 0) cat(" (", partial_cov, " partial)")
    cat("\n")
  }

  cat("Done! Exported", length(all_data), "/", length(titles),
      "queries to", export_dir, "\n")
  invisible(all_data)
}

#' 전체 쿼리 RDS 캐시 로드 (rgcam 불필요)
load_cached_full <- function(region = target_region, output_path = output_dir) {
  region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
  rds_path <- file.path(output_path, "query_export_full",
                        paste0("all_queries_full_", region_tag, ".rds"))
  if (!file.exists(rds_path)) {
    stop("No cached data at: ", rds_path, "\nRun export_all_from_db() first.")
  }
  cat("Loading:", rds_path, "\n")
  data <- readRDS(rds_path)
  cat("Loaded", length(data), "queries\n")
  data
}

#' .dat 캐시 쿼리를 CSV + RDS로 저장 (기존 기능)
export_all <- function(region = target_region, format = "both",
                       output_path = output_dir, .prj = prj) {
  if (is.null(.prj)) stop("No .dat file loaded.")
  queries <- listQueries(.prj)
  export_dir <- file.path(output_path, "query_export")
  if (!dir.exists(export_dir)) dir.create(export_dir, recursive = TRUE)

  all_data <- list()
  index <- data.frame(
    number = integer(), query_name = character(),
    n_rows = integer(), columns = character(),
    stringsAsFactors = FALSE
  )

  cat("Exporting", length(queries), "cached queries",
      if (!is.null(region)) paste0("(region: ", region, ")") else "(all regions)",
      "\n\n")

  for (i in seq_along(queries)) {
    qname <- queries[i]
    cat(sprintf("[%02d/%02d] %s ... ", i, length(queries), qname))
    result <- tryCatch(getQuery(.prj, qname), error = function(e) {
      cat("ERROR:", e$message, "\n"); return(NULL)
    })
    if (is.null(result)) next
    if (!is.null(region) && "region" %in% names(result))
      result <- result %>% filter(region == !!region)

    all_data[[qname]] <- result
    index <- rbind(index, data.frame(
      number = i, query_name = qname, n_rows = nrow(result),
      columns = paste(names(result), collapse = "; "), stringsAsFactors = FALSE
    ))
    if (format %in% c("csv", "both")) {
      csv_path <- file.path(export_dir, paste0(sprintf("%02d", i), "_", sanitize_name(qname), ".csv"))
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

################################################

########## Auto-run ##########
cat("--- Cached Queries (.dat) ---\n")
list_queries()

cat("\n--- Usage ---\n")
cat("  # Cached queries (.dat, fast):\n")
cat("  list_queries()                    # List cached queries\n")
cat("  get_query(5)                      # Get cached query #5\n")
cat("  export_all()                      # Export cached to CSV+RDS\n")
cat("\n")
cat("  # Full queries (Main_queries.xml, 335 total):\n")
cat("  list_all_queries()                # List ALL 335 queries\n")
cat("  list_all_queries(\"elec\")          # Filter by name\n")
cat("  run_db_query(10)                  # Run query #10 from DB (all scenarios)\n")
cat("  run_db_query(10, c(\"S1\",\"S08\"))   # Run with specific scenarios\n")
cat("  run_db_query(\"resource supply\")   # Run by name\n")
cat("  export_all_from_db()              # Export ALL from DB (all scenarios)\n")
cat("  export_all_from_db(c(\"S1\",\"S08\")) # Export specific scenarios\n")
cat("  load_cached_full()                # Load full RDS cache\n")
cat("-------------\n\n")
##############################


