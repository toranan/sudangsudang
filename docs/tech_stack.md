# 기술 스택과 선택 근거

> 최종 확인: 2026-07-17. 이 문서는 현재 저장소에서 확인한 구현만 기록합니다.

## iOS Client

| 영역 | 기술 | 사용 위치 |
|---|---|---|
| 언어/UI | Swift 5, SwiftUI | 사장님/알바생 역할별 화면 |
| 비동기 처리 | Swift Concurrency | 인증, DB 조회, Edge Function 호출 |
| 인증 SDK | Supabase Swift, Kakao iOS SDK | 세션 관리와 카카오 로그인 |
| 실시간 표시 | ActivityKit, WidgetKit | 출근 중 Live Activity 관련 코드 |
| 분석 | Firebase Analytics | 앱 이벤트 수집 |

SwiftUI는 역할별 정보 구조를 빠르게 반복하기 위해 선택했습니다. 네트워크 호출은 `async/await`를 사용하며, 프로젝트는 현재 Swift 5 언어 모드입니다. Swift 6 언어 모드 전환 전에는 격리 규칙을 별도로 점검해야 합니다.

## Backend

| 영역 | 기술 | 선택 이유 |
|---|---|---|
| BaaS | Supabase | 인증, DB, RLS, Function을 한 권한 체계에서 운영 |
| Database | PostgreSQL | 관계형 근태 데이터, 제약 조건, 트랜잭션 |
| Authorization | Row Level Security | 클라이언트 필터와 독립적인 매장/역할 권한 경계 |
| Serverless | Supabase Edge Functions | 시크릿이 필요한 로그인, 계정 삭제, RAG 호출 |

현재 Edge Function은 다음 세 개입니다.

- `kakao-login`: 카카오 인증과 Supabase 세션 연결
- `delete-account`: 인증 사용자 계정 삭제
- `store-rag`: 문서 인덱싱과 매장별 질의

급여 계산과 푸시 알림은 Edge Function에 구현되어 있지 않습니다. 급여는 현재 iOS 클라이언트에서 예상치로 계산합니다.

## RAG

| 역할 | 현재 구현 |
|---|---|
| 임베딩 | OpenAI `text-embedding-3-small`, 1536차원 |
| 저장/검색 | `store_documents.embedding`, pgvector HNSW 인덱스 |
| 답변 생성 | Gemini, 기본값 `gemini-2.5-flash` |
| 실행 위치 | Supabase `store-rag` Edge Function |
| 권한 | 사용자 Bearer token + RLS + `store_id` RPC 필터 |

```text
index: title + content -> embedding -> store_documents
ask: question -> embedding -> store_id별 top 5 -> similarity >= 0.2 -> Gemini
```

현재는 텍스트 문서 하나를 벡터 하나로 저장합니다. PDF 업로드, 청킹, 질문 캐시, 평가 파이프라인은 구현 전 Roadmap 항목입니다.

## 데이터 흐름

```text
SwiftUI App
  |-- Kakao SDK -> kakao-login -> Supabase Auth
  |-- Supabase Client -> PostgreSQL + RLS
  |-- store-rag -> OpenAI Embeddings
                  -> pgvector search
                  -> Gemini answer
```

## 검증 상태

- 2026-07-17 generic iOS Simulator 빌드 성공
- DB 제약과 RLS는 migration으로 관리
- 급여 스냅샷, 야간수당, 최신 요청 검증 단위 테스트 5개 통과
- 급여 경계값과 RLS 통합 테스트는 추가 보강 필요
- 구식 SwiftUI `onChange` API의 deprecation 경고가 남아 있음
