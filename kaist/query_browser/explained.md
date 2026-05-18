# query_browser.R 코드 한줄한줄 설명

> R을 전혀 모르는 사람을 위한 설명입니다.

---

## 기본 R 문법 미리 알기

| 문법                    | 의미                             | 예시                                               |
| --------------------- | ------------------------------ | ------------------------------------------------ |
| `<-`                  | 변수에 값 저장 (= 와 같음)              | `x <- 5` → x에 5 저장                               |
| `c(...)`              | 여러 값을 하나의 리스트(벡터)로 묶기          | `c(1, 2, 3)`                                     |
| `function(x) { ... }` | 함수 정의                          | `add <- function(a, b) { a + b }`                |
| `library(...)`        | 패키지(라이브러리) 불러오기                | Python의 `import`와 같음                             |
| `source("file.R")`    | 다른 R 파일 실행                     | Python의 `exec(open(...).read())`와 같음             |
| `%>%`                 | 파이프 연산자: 앞의 결과를 뒤 함수의 첫 인자로 전달 | `data %>% filter(x > 5)` = `filter(data, x > 5)` |
| `!!`                  | dplyr에서 변수의 값을 그대로 사용하겠다는 표시   | `filter(region == !!region)`                     |
| `NULL`                | "값 없음" (Python의 `None`)        |                                                  |
| `TRUE` / `FALSE`      | 참/거짓 (Python의 `True`/`False`)  |                                                  |
| `cat(...)`            | 화면에 텍스트 출력 (Python의 `print`)   |                                                  |
| `invisible(x)`        | 값을 리턴하되 화면에 자동 출력하지 않음         |                                                  |

---

## 1~25줄: 파일 헤더 (주석)

```r
################################################################################
# GCAM Query Browser
#
# PURPOSE:
#   .dat 프로젝트 파일에서 모든 GCAM 쿼리 결과를 번호로 빠르게 조회하고,
#   특정 region(기본: South Korea)의 전체 쿼리 결과를 CSV/RDS로 일괄 저장.
# ...
################################################################################
```

- `#`으로 시작하는 줄은 **주석** (실행되지 않는 설명)
- 이 파일이 무엇을 하는지, 어떻게 사용하는지 설명

---

## 27~31줄: 라이브러리 로드

```r
library(rgcam)   # GCAM 데이터베이스와 통신하는 패키지
library(dplyr)   # 데이터 필터링/변환 도구 (filter, mutate 등)
library(here)    # 프로젝트 루트 경로를 자동으로 찾아주는 패키지
```

- `library()` = 패키지를 메모리에 로드
- Python에서 `import pandas as pd` 하는 것과 같음
- **rgcam**: GCAM BaseX 데이터베이스에서 쿼리 결과를 가져오는 R 패키지
- **dplyr**: 테이블 데이터를 쉽게 조작하는 도구 (SQL의 WHERE, SELECT 같은 기능)
- **here**: 현재 프로젝트의 루트 폴더 경로를 자동으로 찾아줌

---

## 33~35줄: 설정 파일 로드

```r
source(file.path(here(), "kaist/config.R"))
```

- `here()` → 프로젝트 루트 경로 반환 (예: `"C:/GCAM/gcamreport"`)
- `file.path(A, B)` → 경로를 안전하게 결합 (예: `"C:/GCAM/gcamreport/kaist/config.R"`)
- `source(...)` → 해당 R 파일을 **실행** → config.R에 정의된 변수들이 메모리에 로드됨
  - `project_dir` = `"C:/GCAM/gcamreport/kmip"` (데이터 폴더)
  - `output_dir` = `"C:/GCAM/gcamreport/kmip/DB25_output"` (출력 폴더)
  - `target_region` = `"South Korea"` (기본 지역)

---

## 37~65줄: 프로젝트 파일(.dat) 로드

### 40~44줄: .dat 파일 찾기

```r
prj_files <- c(
  list.files(project_dir, pattern = ".*project_.*\\.dat$", full.names = TRUE),
  list.files(output_dir,  pattern = ".*project_.*\\.dat$", full.names = TRUE)
)
prj_files <- unique(prj_files)
```

- `list.files(폴더, pattern)` → 해당 폴더에서 패턴에 맞는 파일 목록을 반환
- `pattern = ".*project_.*\\.dat$"` → 파일명에 "project_"가 포함되고 ".dat"으로 끝나는 파일
  - `.*` = 아무 문자 0개 이상
  - `\\.` = 마침표(.) 문자 그대로
  - `$` = 문자열 끝
- `full.names = TRUE` → 전체 경로 포함 (예: `"C:/GCAM/.../project_20260120.dat"`)
- `c(A, B)` → 두 폴더의 검색 결과를 하나로 합침
- `unique()` → 중복 제거

### 46~49줄: 파일이 없으면 에러

```r
if (length(prj_files) == 0) {
  stop("No .dat project file found in:\n  ", project_dir, "\n  ", output_dir,
       "\nRun step1_generate_report.R first.")
}
```

- `length()` → 리스트의 길이 (파일이 몇 개인지)
- `stop(...)` → 에러 메시지를 출력하고 **실행 중단** (Python의 `raise Exception`)
- .dat 파일이 하나도 없으면 = step1을 아직 안 돌린 것 → 안내 메시지 출력

### 51~52줄: 가장 최신 파일 선택 후 로드

```r
prj_file <- prj_files[order(file.mtime(prj_files), decreasing = TRUE)[1]]
prj <- loadProject(prj_file)
```

- `file.mtime()` → 파일의 **수정 시간** 반환
- `order(..., decreasing = TRUE)` → 최신 순으로 정렬한 **인덱스** 반환
- `[1]` → 첫 번째 (= 가장 최신) 선택
- `loadProject()` → rgcam 함수: .dat 파일을 메모리에 로드
  - 결과: `prj`라는 R 객체 (중첩 리스트 구조)
  - 구조: `prj[["시나리오이름"]][["쿼리이름"]]` → 테이블 데이터

### 54~55줄: 시나리오와 쿼리 목록 추출

```r
.qb_scenarios <- listScenarios(prj)
.qb_queries <- listQueries(prj)
```

- `listScenarios()` → 프로젝트에 포함된 시나리오 이름 목록 (예: `"Ref_Con ...", "05_nzM_Adv_plus ..."`)
- `listQueries()` → 프로젝트에 포함된 쿼리 이름 목록 (예: `"CO2 emissions by region", "elec gen by gen tech", ...`)
- 변수명 앞의 `.qb_` → 내부용 변수라는 관례 (다른 코드와 이름 충돌 방지)

### 57~64줄: 요약 정보 출력

```r
cat("\n========================================\n")
cat("  GCAM Query Browser\n")
cat("Project file:", basename(prj_file), "\n")
cat("Scenarios:   ", length(.qb_scenarios), "-", paste(.qb_scenarios, collapse = ", "), "\n")
cat("Queries:     ", length(.qb_queries), "\n")
```

- `cat()` → 화면에 텍스트 출력
- `basename()` → 전체 경로에서 파일명만 추출 (예: `"project_20260120_161224.dat"`)
- `paste(..., collapse = ", ")` → 여러 문자열을 쉼표로 연결
- `\n` → 줄바꿈

---

## 67~73줄: 헬퍼 함수 - sanitize_name

```r
sanitize_name <- function(x) {
  x <- gsub("[^a-zA-Z0-9_]", "_", x)   # 영문/숫자/밑줄 외 문자를 _로 교체
  x <- gsub("_+", "_", x)               # 연속된 __를 하나의 _로
  x <- gsub("^_|_$", "", x)             # 앞뒤 _ 제거
  substr(x, 1, 100)                      # 100자까지만 자름
}
```

- **목적**: 쿼리 이름을 **파일명으로 안전하게** 변환
- 예: `"CO2 emissions by region"` → `"CO2_emissions_by_region"`
- `gsub(패턴, 대체문자, 텍스트)` → 정규식으로 문자열 치환 (Python의 `re.sub()`)
- `substr(x, 1, 100)` → 1번째~100번째 문자까지만 (너무 긴 이름 방지)

---

## 82~89줄: list_queries() 함수

```r
list_queries <- function(.prj = prj) {
  queries <- listQueries(.prj)          # 전체 쿼리 이름 목록 가져오기
  width <- nchar(length(queries))       # 번호 자릿수 계산 (74개면 2자리)
  for (i in seq_along(queries)) {       # 1부터 끝까지 반복
    cat(sprintf("[%0*d] %s\n", width, i, queries[i]))  # [01] 쿼리이름 형식 출력
  }
  invisible(queries)                     # 쿼리 목록을 리턴 (화면 출력 없이)
}
```

- **목적**: 모든 쿼리를 번호와 함께 출력
- `seq_along(queries)` → `1, 2, 3, ..., 74` (쿼리 개수만큼)
- `sprintf("[%0*d] %s\n", width, i, queries[i])` → 포맷팅된 문자열
  - `%0*d` → 숫자를 width 자릿수로, 앞에 0 채움 (예: `01`, `02`)
  - `%s` → 문자열 삽입
- 출력 예: `[01] CO2 emissions by region`
- `.prj = prj` → 기본값: 전역변수 `prj` 사용 (다른 프로젝트도 가능)

---

## 98~144줄: get_query() 함수 (핵심)

### 함수 선언 (98줄)

```r
get_query <- function(n, region = target_region, scenario = NULL, .prj = prj) {
```

- `n` → 필수: 쿼리 번호(숫자) 또는 이름(문자열)
- `region = target_region` → 선택: 기본값 "South Korea" (NULL이면 전체)
- `scenario = NULL` → 선택: 기본값 전체 시나리오
- `.prj = prj` → 선택: 기본값 현재 로드된 프로젝트

### 101~121줄: 쿼리 이름 결정

```r
if (is.numeric(n)) {                    # n이 숫자면
  if (n < 1 || n > length(queries)) {   #   범위 확인
    stop("Query number out of range.")
  }
  query_name <- queries[n]              #   번호로 쿼리명 조회
} else if (is.character(n)) {            # n이 문자열이면
  matches <- grep(n, queries, ignore.case = TRUE)  # 부분 매칭 검색
  if (length(matches) == 0) {           #   매칭 없으면 에러
    stop("No query matching '", n, "'")
  }
  if (length(matches) > 1) {            #   매칭이 여러 개면 목록 출력
    cat("Multiple matches found:\n")
    for (m in matches) { cat(sprintf("  [%d] %s\n", m, queries[m])) }
    cat("Using first match: ...\n")
  }
  query_name <- queries[matches[1]]     #   첫 번째 매칭 사용
}
```

- `is.numeric(n)` → n이 숫자인지 확인
- `grep(패턴, 목록)` → 패턴이 포함된 항목의 **위치(인덱스)** 반환
  - 예: `grep("elec gen", queries)` → `elec gen`이 포함된 쿼리들의 번호
  - `ignore.case = TRUE` → 대소문자 무시

### 123~128줄: 쿼리 실행

```r
result <- tryCatch(
  getQuery(.prj, query_name),      # rgcam에서 쿼리 데이터 가져오기
  error = function(e) {             # 에러 발생 시
    stop("Failed to get query '", query_name, "': ", e$message)
  }
)
```

- `getQuery(prj, "쿼리이름")` → rgcam 함수: .dat에서 해당 쿼리의 테이블 데이터 추출
  - 반환: tibble (= 데이터프레임, 엑셀 시트와 비슷)
  - 컬럼: scenario, region, year, value, technology 등
- `tryCatch(코드, error = 처리함수)` → Python의 `try/except`와 같음

### 130~135줄: 지역/시나리오 필터링

```r
if (!is.null(region) && "region" %in% names(result)) {
  result <- result %>% filter(region == !!region)
}
if (!is.null(scenario) && "scenario" %in% names(result)) {
  result <- result %>% filter(scenario == !!scenario)
}
```

- `!is.null(region)` → region 값이 지정되었으면 (NULL이 아니면)
- `"region" %in% names(result)` → 결과 테이블에 "region" 컬럼이 있으면
- `result %>% filter(region == !!region)` → region 컬럼이 지정값인 행만 남김
  - `%>%` = 파이프: `result`를 `filter()`에 전달
  - `!!region` = 변수의 **값**을 사용 (dplyr 문법 특수성)
  - SQL로 치면: `SELECT * FROM result WHERE region = 'South Korea'`

### 137~143줄: 결과 정보 출력 후 리턴

```r
cat("Query: ", query_name, "\n")
cat("Rows:  ", nrow(result), "\n")          # 행 수
cat("Cols:  ", paste(names(result), collapse = ", "), "\n")  # 컬럼 목록
if (!is.null(region)) cat("Region:", region, "\n")
result   # 마지막 줄 = 리턴값 (R은 return() 없이도 마지막 값이 리턴됨)
```

---

## 152~222줄: export_all() 함수

### 152~153줄: 함수 선언

```r
export_all <- function(region = target_region, format = "both",
                       output_path = output_dir, .prj = prj) {
```

- `format = "both"` → "csv", "rds", 또는 "both" (둘 다)

### 154~165줄: 준비

```r
queries <- listQueries(.prj)                    # 전체 쿼리 목록
export_dir <- file.path(output_path, "query_export")  # 저장 폴더
if (!dir.exists(export_dir)) dir.create(export_dir, recursive = TRUE)  # 폴더 없으면 생성

all_data <- list()          # 빈 리스트 (모든 쿼리 결과를 여기에 모음)
index <- data.frame(...)    # 빈 테이블 (쿼리 인덱스 정보)
```

- `dir.create(..., recursive = TRUE)` → 중간 폴더까지 한번에 생성 (Python의 `os.makedirs`)

### 171~207줄: 모든 쿼리를 순회하며 저장

```r
for (i in seq_along(queries)) {        # 1번 쿼리부터 마지막까지 반복
  qname <- queries[i]                  # 현재 쿼리 이름
  cat(sprintf("[%02d/%02d] %s ... ", i, length(queries), qname))  # 진행상황 출력

  result <- tryCatch(                  # 쿼리 실행 (에러 시 건너뜀)
    getQuery(.prj, qname),
    error = function(e) { cat("ERROR:", e$message, "\n"); return(NULL) }
  )
  if (is.null(result)) next            # 에러였으면 다음 쿼리로

  # region 필터링
  if (!is.null(region) && "region" %in% names(result)) {
    result <- result %>% filter(region == !!region)
  }

  all_data[[qname]] <- result          # 결과를 리스트에 쿼리이름으로 저장

  # 인덱스 테이블에 행 추가
  index <- rbind(index, data.frame(number = i, query_name = qname, ...))

  # CSV로 저장
  if (format %in% c("csv", "both")) {
    csv_path <- file.path(export_dir, paste0(sprintf("%02d", i), "_", sanitize_name(qname), ".csv"))
    write.csv(result, csv_path, row.names = FALSE)
  }
}
```

- `next` → 루프에서 현재 반복을 건너뛰고 다음으로 (Python의 `continue`)
- `all_data[[qname]]` → 리스트에 이름(key)으로 접근 (Python의 딕셔너리와 같음)
- `rbind()` → 테이블에 새 행 추가 (row bind)
- `write.csv()` → 테이블을 CSV 파일로 저장
- `row.names = FALSE` → 행 번호 저장하지 않음

### 209~221줄: RDS 저장 및 마무리

```r
if (format %in% c("rds", "both")) {
  region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
  rds_path <- file.path(export_dir, paste0("all_queries_", region_tag, ".rds"))
  saveRDS(all_data, rds_path)           # 전체 데이터를 하나의 RDS 파일로 저장
}

index_path <- file.path(export_dir, "query_index.csv")
write.csv(index, index_path, row.names = FALSE)  # 인덱스 테이블도 CSV로 저장
```

- `saveRDS(객체, 경로)` → R 객체를 바이너리 파일로 저장
  - RDS = R의 직렬화 포맷 (빠르고 타입 보존됨)
  - 나중에 `readRDS(경로)`로 그대로 복원 가능
- `gsub(" ", "_", "South Korea")` → `"South_Korea"` (공백을 밑줄로)

---

## 229~241줄: load_cached() 함수

```r
load_cached <- function(region = target_region, output_path = output_dir) {
  region_tag <- if (!is.null(region)) gsub(" ", "_", region) else "all_regions"
  rds_path <- file.path(output_path, "query_export",
                        paste0("all_queries_", region_tag, ".rds"))
  if (!file.exists(rds_path)) {         # RDS 파일이 없으면 에러
    stop("No cached data found. Run export_all() first.")
  }
  data <- readRDS(rds_path)             # RDS 파일 읽기 → named list 복원
  data                                   # 리턴
}
```

- **목적**: rgcam 라이브러리 없이도 저장된 데이터를 바로 사용
- `export_all()`을 한번 실행한 후, 이후 세션에서는 이 함수만으로 데이터 접근 가능
- 반환값: `data[["쿼리이름"]]`으로 원하는 쿼리 결과 테이블에 접근

---

## 245~256줄: 자동 실행 부분

```r
list_queries()   # 스크립트를 source()하면 자동으로 쿼리 목록 출력

cat("\n--- Usage ---\n")
cat("  list_queries()              # Show all queries\n")
cat("  get_query(5)                # Get query #5 (South Korea)\n")
# ... 사용법 안내 출력
```

- `source("kaist/query_browser.R")`를 실행하면 함수 정의 후 이 부분이 자동 실행됨
- 번호 매긴 쿼리 목록 + 사용법이 콘솔에 바로 출력됨

---

## 전체 데이터 흐름 요약

```
GCAM BaseX DB
    ↓ step1에서 rgcam::runQuery()로 쿼리 실행
.dat 파일 (캐시된 쿼리 결과, 약 76개)
    ↓ query_browser.R에서 rgcam::loadProject()로 로드
prj 객체 (메모리의 중첩 리스트)
    ↓ list_queries()로 목록 확인
    ↓ get_query(번호)로 개별 조회
    ↓ export_all()로 일괄 저장
CSV 파일들 + RDS 파일
    ↓ load_cached()로 재로드 (rgcam 불필요)
named list → data[["쿼리이름"]] → 테이블
```
