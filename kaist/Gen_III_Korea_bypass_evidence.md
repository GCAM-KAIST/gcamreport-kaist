# Gen_III_Korea가 "e nuclear" Fuel Market을 Bypass하는 증거

## 배경

GCAM에서 Primary Energy|Nuclear는 "e nuclear" fuel market 기반으로 집계됩니다.
그러나 Gen_III_Korea의 발전량이 이 집계에 포함되지 않는 현상이 발견되었습니다.

## 데이터 비교 (Ref_Con 시나리오, South Korea)

| 연도 | e_nuclear (EJ) | Gen_II_LWR (EJ) | Gen_III_Korea (EJ) | Total Nuclear (EJ) |
|------|----------------|-----------------|--------------------|--------------------|
| 2020 | 0.573 | 0.548 | 0.030 | 0.578 |
| 2025 | 0.544 | 0.521 | 0.180 | 0.701 |
| 2030 | 0.502 | 0.485 | 0.330 | 0.815 |
| 2035 | 0.444 | 0.433 | 0.439 | 0.872 |
| 2040 | 0.375 | 0.369 | 0.534 | 0.903 |
| 2045 | 0.301 | 0.296 | 0.565 | 0.862 |
| 2050 | 0.227 | 0.224 | 0.462 | 0.686 |

## 핵심 증거

### 차이 분석

| 비교 대상 | 평균 절대 차이 |
|-----------|---------------|
| e_nuclear vs Gen_II_LWR | **0.0129 EJ** (거의 일치) |
| e_nuclear vs Total Nuclear | **0.3499 EJ** (큰 차이) |

### 결론

```
e_nuclear ≈ Gen_II_LWR        (차이 = 0.013 EJ, ~2.5%)
e_nuclear ≠ Gen_II_LWR + Gen_III_Korea (차이 = 0.35 EJ, ~40%)
```

**→ "e nuclear" fuel market에는 Gen_II_LWR만 포함되고, Gen_III_Korea는 포함되지 않음**

## 원인 분석

### GCAM 모델 데이터 플로우

```
┌─────────────────────────────────────────────────────────────────────┐
│                     GCAM Model Structure                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Gen_II_LWR ──────► "e nuclear" fuel market ──► Primary Energy      │
│                            │                     Query              │
│                            ▼                                        │
│                       electricity                                   │
│                                                                     │
│  Gen_III_Korea ────────────────────────────────► electricity        │
│  (Korea custom)      (bypasses "e nuclear"!)                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 쿼리별 동작

| GCAM Query | 집계 기준 | Gen_III_Korea 포함? |
|------------|----------|---------------------|
| `elec gen by gen tech` | Technology 이름 | ✅ 포함 |
| `primary energy consumption` | Fuel market | ❌ 누락 |

## step2_process_data.R 수정의 정당성

### 왜 수정이 필요한가?

1. **GCAM 모델 설정 이슈**: Gen_III_Korea는 한국 특화 커스텀 기술로, "e nuclear" fuel market을 거치지 않도록 설정됨
2. **Primary Energy Query의 한계**: Fuel market 기반 집계로 인해 Gen_III_Korea 누락
3. **Secondary Energy와의 불일치**: elec gen query는 Gen_III_Korea 포함, primary energy query는 누락

### step2의 Gen_III_Korea Primary Energy Fix

```r
########## Gen_III_Korea Primary Energy Fix ##########
gen3_korea_gen <- elec_gen %>%
  filter(technology == "Gen_III_Korea") %>%
  select(scenario, region, year, value)

if (nrow(gen3_korea_gen) > 0) {
  # Primary Energy|Nuclear에 Gen_III_Korea 발전량 추가
  for (i in 1:nrow(data)) {
    if (data$Variable[i] == "Primary Energy|Nuclear") {
      # Gen_III_Korea 값을 더함
    }
  }
}
```

### 이 수정이 Double Counting이 아닌 이유

- Gen_III_Korea는 원래 Primary Energy|Nuclear에 **포함되지 않았음**
- 추가하는 것은 누락된 값을 보완하는 것
- Manual reporting 결과와 더 가까워짐

## 검증 결과

| 항목 | Without Fix | With Fix | Template (Manual) |
|------|-------------|----------|-------------------|
| 2030 Primary Energy Nuclear | 11,898 ktoe | 19,780 ktoe | 42,035 ktoe |

- **With Fix**가 모든 연도에서 Template에 더 가까움 (6/6)
- 평균 오차: With Fix 20,194 ktoe < Without Fix 28,054 ktoe

---

*생성일: 2026-01-26*
*분석 대상: KMIP2025 GCAM 결과*
