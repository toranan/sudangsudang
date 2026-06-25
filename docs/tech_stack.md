# 오늘얼마? — 기술 스택 정의서

> 소규모 사업장 올인원 HR 플랫폼 (근태관리 + 급여계산 + 매뉴얼 AI)
> 최종 업데이트: 2026-05-08

---

## 📱 Client — iOS Native

| 항목 | 기술 | 비고 |
|---|---|---|
| Language | Swift 6 | Swift Concurrency (async/await) 적극 활용 |
| UI Framework | SwiftUI | |
| 실시간 근무 타이머 | ActivityKit (Live Activity) | 잠금화면 + 다이나믹 아일랜드 |
| 홈화면 위젯 | WidgetKit | 오늘 급여 실시간 표시 |
| 분석 | Firebase Analytics | 유저 행동 및 앱 성능 모니터링 |

---

## 🗄 Backend / Database / Auth

| 항목 | 기술 | 비고 |
|---|---|---|
| BaaS | Supabase | |
| Database | PostgreSQL 17 | |
| 인증 | Supabase Auth + Kakao OAuth | Edge Function으로 소셜 로그인 처리 |
| 보안 | Row Level Security (RLS) | `store_id` 기반 가게별 완전 격리 |
| 서버리스 | Supabase Edge Functions (Deno 2) | 급여 계산, 푸시 알림, 계정 삭제 등 |

### 현재 DB 스키마 구조
```
profiles → stores → workers → work_logs
                            → invites
                            → evaluations  (상호 평가)
                            → schedules    (스케줄 관리)
```

---

## 🤖 AI — 사업장 맞춤 매뉴얼 AI (Multi-tenant RAG)

> 사장님이 올린 매뉴얼(포스기 마감법, 레시피, 지시사항 등)을 기반으로
> 알바생 질문에 AI가 24시간 정확하게 답변하는 "사업장 전용 AI 매니저"

### 모델 선택 (2026년 5월 기준)

| 역할 | 모델 | 이유 |
|---|---|---|
| **LLM (답변 생성)** | `gpt-5.4-mini` | 낮은 레이턴시 + 비용 효율, 한국어 품질 충분 |
| **LLM (복잡 추론)** | `gpt-5.5` | 매뉴얼 재색인, 요약 등 무거운 작업에만 선택적 사용 |
| **임베딩** | `text-embedding-3-small` | 1,536차원, $0.02/1M tokens, 한국어 충분 |

> **참고:** GPT-4o는 2026년 2월 ChatGPT에서 deprecated. API는 유지되나 신규 개발은 GPT-5.x 권장.
> `gpt-5.4-nano`는 초저비용 옵션으로 FAQ 캐시 미스 시 1차 답변용으로도 고려 가능.

### Vector DB 전략

| 상황 | 기술 | 비고 |
|---|---|---|
| **MVP ~ 수백만 벡터** | pgvector (Supabase 내장) + HNSW 인덱스 | 별도 인프라 없이 PostgreSQL에 통합 |
| **수천만 벡터 이상 스케일업** | Supabase Vector Buckets | S3 기반 대용량 벡터 스토리지, pgvector와 병행 가능 |

> **2026 권장 인덱스:** IVFFlat → **HNSW**로 전환. 더 높은 recall + 낮은 레이턴시, 데이터 없이도 인덱스 선생성 가능.

### RAG 파이프라인 아키텍처

```
[사장님 매뉴얼 업로드 (텍스트/PDF)]
        ↓
  청킹 + 임베딩 생성 (text-embedding-3-small)
        ↓
  store_documents 테이블에 저장 (store_id 태깅)
  → HNSW 인덱스 자동 갱신
        ↓
[알바생 질문 입력]
        ↓
  1. rag_cache 캐시 테이블 확인 (질문 해시 매칭)
     ↳ 캐시 HIT → 즉시 답변 반환 (API 비용 0)
     ↳ 캐시 MISS ↓
  2. store_id 필터 + 벡터 유사도 검색 (pgvector HNSW)
        ↓
  3. 검색된 컨텍스트 + 질문 → gpt-5.4-mini
        ↓
  4. 답변 생성 → rag_cache 저장 → 알바생에게 전달
```

### 멀티테넌트 격리 원칙

```sql
-- 벡터 검색 시 반드시 store_id 선행 필터링
SELECT content, embedding <=> query_embedding AS distance
FROM store_documents
WHERE store_id = $1          -- 1. 테넌트 격리 (RLS + 명시적 WHERE)
ORDER BY distance
LIMIT 5;
```

> RLS와 WHERE 절 이중 적용 → 가게 간 매뉴얼 데이터 교차 원천 차단

### 추가 DB 스키마 (RAG용)

```sql
-- 매뉴얼 청크 + 벡터
CREATE TABLE store_documents (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id    uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  title       text,
  content     text NOT NULL,
  embedding   vector(1536),       -- text-embedding-3-small 차원
  metadata    jsonb,              -- 파일명, 페이지, 카테고리 등
  created_at  timestamptz DEFAULT now()
);
CREATE INDEX ON store_documents USING hnsw (embedding vector_cosine_ops);

-- 반복 질문 캐싱 (API 비용 절감)
CREATE TABLE rag_cache (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id       uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  question_hash  text NOT NULL,   -- SHA-256 해시
  answer         text NOT NULL,
  hit_count      int DEFAULT 1,
  created_at     timestamptz DEFAULT now(),
  UNIQUE (store_id, question_hash)
);
```

---

## 🏗 전체 아키텍처 요약

```
iOS App (SwiftUI)
    │
    ├─ Supabase Client SDK
    │       ├─ Auth (Kakao OAuth)
    │       ├─ Database (PostgreSQL + RLS)
    │       │       ├─ 근태/급여 데이터
    │       │       └─ store_documents (pgvector HNSW)
    │       └─ Edge Functions (Deno 2)
    │               ├─ 급여 계산 / 푸시 알림
    │               ├─ RAG 파이프라인 실행
    │               │       └─ OpenAI API (gpt-5.4-mini / text-embedding-3-small)
    │               └─ 계정 삭제 / 카카오 로그인
    │
    └─ Firebase Analytics
```

---

## 💰 AI 비용 예상 (월간 추정)

| 시나리오 | 가게 수 | 월 질문 수 | 예상 비용 |
|---|---|---|---|
| MVP | 100개 | 1,000건 | ~$2–5 |
| 성장기 | 1,000개 | 20,000건 | ~$20–50 |
| 스케일 | 10,000개 | 500,000건 | ~$200–500 |

> 캐시 HIT율 60~80% 가정 시. `rag_cache`로 반복 질문 차단이 비용의 핵심.

---

## 📐 핵심 설계 원칙

1. **멀티테넌트 격리**: 모든 테이블 `store_id` FK + RLS → 타 가게 데이터 접근 불가
2. **추가 인프라 0**: pgvector = Supabase 내장 → Pinecone 등 외부 Vector DB 불필요 (MVP 단계)
3. **비용 방어**: rag_cache → 반복 질문 API 비용 차단, gpt-5.4-mini 우선 사용
4. **점진적 스케일업**: pgvector MVP → Vector Buckets (수천만 벡터 이상 시 병행 전환)
