# generate_report (step1) Troubleshooting Log

DB: DB26 | GCAM 7.0 | Date: 2026-03-28~29

## 1. saveDataFiles 재실행으로 인한 에러

### 원인
`saveDataFiles_GCAM7.0.R`을 재실행하면 **모든 .rda 파일이 재생성**된다.
이전 .rda (1월 생성)에는 없던 template 항목들이 현재 CSV에는 추가되어 있어서,
재생성된 .rda에 새 변수가 포함됨 → `generate_report`가 로드 시도 → 실패.

### 영향받은 변수 (GCAM 7.0에서 미지원 또는 쿼리 없음)
| 변수 | 원인 | 해결 |
|------|------|------|
| `income_clean` | 7.1+ 전용 (`subregional income` 쿼리) | template 필터 |
| `consumption_hh_clean` | 7.1+ 전용 (`food demand prices` 쿼리) | template 필터 |
| `iron_steel_map` | rgcam이 `industry final energy by tech and fuel` 못 가져옴 | template 필터 |
| `ag_trade` | rgcam이 `ag import vs. domestic supply` 못 가져옴 | template 필터 |
| `trade_clean` | `ag_trade`에 dependency | template 필터 |

### 해결: saveDataFiles_GCAM7.0.R에 template 필터 추가
```r
template_v7.0 <- template_v7.0 %>%
  dplyr::filter(!Internal_variable %in% c("income_clean", "consumption_hh_clean",
                                           "iron_steel_map", "ag_trade", "trade_clean"))
use_data(template_v7.0, overwrite = T)
```

## 2. rgcam 쿼리 실행 문제

### 증상
- `generate_report` → `create_project`에서 일부 쿼리가 빈 결과 반환
- 특히 `buildList="true"` 속성이 있는 쿼리에서 문제
- Model Interface GUI에서는 같은 쿼리가 정상 작동

### 원인: rgcam의 runQuery 내부 문제 2가지

#### (a) `character(0)` 접두어
`parse_batch_query()`가 쿼리를 3-element list로 반환:
- `[[1]]`: `character(0)` (빈 벡터)
- `[[2]]`: XML 문자열 (실제 쿼리)
- `[[3]]`: 쿼리 제목

이걸 `paste0("mi:runMIQuery(", query, ...)`에 넣으면 XQuery에 `character(0)`이 포함 →
BaseX가 `fn:character(0)`으로 파싱 → `Unknown function: fn:character` 에러.

**해결 (rgcam_patch.R에 적용):**
```r
if (is.list(query)) {
  query <- query[[2]]
}
```

#### (b) buildList 쿼리 실패
`buildList="true"` 속성이 있는 쿼리(ag import, industry final energy 등)는
rgcam의 RunMIQuery 모듈이 `OPEN DB; RUN file` 방식으로 제대로 처리 못함.
(원래 `-i DB` 방식에서는 작동했을 수 있으나 BaseX 9.5+ 호환 패치 후 실패)

### 핵심 발견: `unavailable_query.R`로 직접 테스트하면 64개 쿼리 전부 OK

`unavailable_query.R`은 rgcam의 `runQuery()` 대신 **BaseX CLI를 직접 호출**하고,
`xml2`로 파싱한 깨끗한 XML을 `mi:runMIQuery()`에 전달 → 모든 쿼리 성공.

| 방식 | 쿼리 실행 | buildList 처리 | 결과 |
|------|----------|---------------|------|
| rgcam `runQuery()` | 패키지 내부 경로 | 일부 실패 | 빈 결과 |
| `unavailable_query.R` | BaseX CLI 직접 | 정상 | 64/64 OK |
| Model Interface GUI | Java embedded | 정상 | OK |

**결론:** DB에 데이터는 있으나, rgcam의 쿼리 전달 방식 버그로 일부 못 가져옴.
template 필터는 **임시 우회**이며, 근본 해결은 rgcam_patch 개선 필요.

## 3. desired_variables = "All" vs target_var

### 증상
`desired_variables = target_var`로 설정하면 `ag_price_wld`에서
`food_items_map_v7.0` 매핑 에러 (`sector = NA`).

### 원인
`filter_variables()`가 template 변수에 없는 **내부 중간 변수**
(예: `Agricultural Demand|Crops|Food|Corn`)를 제거 →
`right_join`에서 매치 실패 → `sector = NA` 생성.

### 해결
`desired_variables = "All"` 사용. "All"이면 `filter_variables()` 스킵.

## 4. DB26 시나리오 구성

DB26에 5개 시나리오 (이름 중복 포함):
| name | date | 비고 |
|------|------|------|
| S1 | 2026-03-24 10:57 | 이전 run |
| S1 | 2026-03-28 19:53 | **최신 (사용)** |
| S8 | 2026-03-24 09:49 | 불필요 |
| S08 | 2026-03-28 20:47 | 필요 |
| 05_nzL1b_Adv_plus | 2025-11-24 | 필요 |

필요한 시나리오: `c("S1", "S08", "05_nzL1b_Adv_plus")`
rgcam은 동일 이름 시나리오 중 **최신 것**을 사용.

## 5. 도구 정리

| 파일 | 용도 |
|------|------|
| `kaist/unavailable_query.R` | .dat 없이 DB 직접 쿼리 가능 여부 확인 + saveDataFiles 필터 제안 |
| `kaist/rgcam_patch.R` | BaseX 9.5+ 호환 + `character(0)` 접두어 제거 |
| `kaist/query_browser_without_dat.R` | Main_queries.xml 335개 쿼리 직접 실행/export |

## 6. unavailable_query.R vs rgcam

`unavailable_query.R`은 rgcam의 **쿼리 실행 함수를 사용하지 않는다.**
`rgcam:::DEFAULT.MICLASSPATH()`로 JAR 파일 경로만 참조하고,
실제 쿼리는 `system2("java", ...)` → BaseX CLI 직접 실행.

따라서 rgcam의 `runQuery()` 버그(`character(0)`, buildList 실패)를 우회한다.
