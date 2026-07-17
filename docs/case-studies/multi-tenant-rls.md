# `store_id`와 RLS 기반 멀티테넌트 격리

## 문제

한 사용자가 여러 매장에 속할 수 있고 사장님과 알바생의 권한도 다릅니다. 클라이언트 필터가 빠지거나 잘못된 `store_id`가 전달돼도 다른 매장의 근태, 직원, 문서가 노출되면 안 됩니다.

## 선택

별도 DB를 매장마다 만드는 대신 공유 PostgreSQL 스키마에 `store_id`를 두고 RLS를 최종 권한 경계로 사용했습니다.

- 사장님: `stores.owner_id = auth.uid()`인 매장 데이터 관리
- 알바생: 활성화된 `workers.user_id = auth.uid()` 연결을 가진 매장 데이터 조회
- 운영 문서: 사장님은 관리, 활성 알바생은 조회만 허용
- RAG 검색: RPC 인자로 `p_store_id`를 받고 쿼리에서도 같은 값으로 제한
- Edge Function: 사용자 Bearer token으로 Supabase client를 생성해 RLS를 그대로 적용

## 구현 근거

- 기본 스키마와 근태 정책: `docs/supabase_schema.sql`
- 근태 정책 강화: `supabase/migrations/20260219_schema_hardening.sql`
- 문서 정책과 검색 RPC: `supabase/migrations/20260708_store_documents.sql`
- 인증 토큰 전달: `supabase/functions/store-rag/index.ts`

## 함께 적용한 무결성 규칙

- 매장/직원별 열린 근무 기록은 하나만 허용
- 퇴근 시간은 출근 시간보다 빠를 수 없음
- 매장/사용자별 직원 연결 중복 방지
- 초대 수락은 DB 함수 안에서 검증과 연결을 함께 처리

## 남은 위험

정책 정의는 있지만 사장님 A, 사장님 B, 소속 알바생, 비소속 알바생을 조합한 자동 통합 테스트가 없습니다. 또한 초기 스키마의 초대 조회 정책은 공개 범위가 넓어 토큰 조회 RPC 중심으로 축소할 필요가 있습니다. 다음 단계는 Supabase 로컬 환경에서 역할별 허용/거부 행렬을 CI로 실행하는 것입니다.
