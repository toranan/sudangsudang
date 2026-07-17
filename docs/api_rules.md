# API And Permission Rules

> 기준: 현재 iOS 호출부, 기본 스키마, migration, Edge Function. 계획 기능은 포함하지 않습니다.

## Authentication

- Supabase Auth 세션을 API 권한의 기준으로 사용합니다.
- 카카오 로그인은 `kakao-login` Edge Function을 거쳐 Supabase 세션과 연결합니다.
- 앱 역할은 `profiles.role`의 `owner` 또는 `worker`입니다.
- Edge Function은 `Authorization: Bearer <token>`을 요구합니다.

## Permission Matrix

| Resource | Owner | Worker |
|---|---|---|
| Store | 본인 소유 매장 생성/조회/수정 | 소속 매장 조회 |
| Worker | 소유 매장의 직원 관리 | 본인 연결 조회 |
| Work log | 소유 매장 기록 조회, 수정, 승인/반려 | 본인 기록 생성, 열린 기록 퇴근, 본인 기록 조회 |
| Schedule | 소유 매장 일정 관리 | 본인 일정 조회 |
| Store document | 소유 매장 문서 관리 | 활성 소속 매장 문서 조회 |
| RAG | 소유 매장 문서 인덱싱/질의 | 활성 소속 매장 질의 |

권한은 화면 노출 여부만으로 판단하지 않고 PostgreSQL RLS에서 다시 검증합니다.

## Invitation

1. 사장님이 매장 초대 토큰을 생성합니다.
2. 로그인한 알바생이 토큰을 입력합니다.
3. `accept_store_invite` DB 함수가 토큰, 만료, 사용자, 중복 연결을 검증합니다.
4. 성공 시 `(store_id, user_id)` 직원 연결을 생성하거나 기존 연결을 활성화합니다.

초기 스키마의 공개 초대 조회 정책은 범위가 넓습니다. 클라이언트 직접 조회보다 검증 RPC만 노출하도록 축소하는 작업이 남아 있습니다.

## Attendance

### Check-in

- 알바생 본인의 `worker_id`와 같은 `store_id`로 열린 `work_log`를 생성합니다.
- 부분 유니크 인덱스가 같은 매장/직원의 중복 열린 기록을 차단합니다.
- 위치나 Wi-Fi 검증은 현재 구현 범위가 아닙니다.

### Check-out

- 알바생은 본인의 열린 기록만 퇴근 처리할 수 있습니다.
- DB 제약이 퇴근 시간이 출근 시간보다 빠른 값을 거부합니다.
- 기록은 사장님 승인 전까지 급여 확정값으로 취급하지 않습니다.

### Approval

- 사장님은 본인 소유 매장의 기록만 승인하거나 반려할 수 있습니다.
- 승인 상태는 저장하지만 적용 급여 조건과 계산 결과 스냅샷은 아직 저장하지 않습니다.

## Store RAG

### `index`

- 사장님이 `storeId`, 제목, 내용, 문서 종류를 전달합니다.
- Edge Function이 임베딩을 생성하고 사용자 토큰이 적용된 DB client로 저장합니다.
- RLS가 해당 매장의 소유자인지 검증합니다.

### `ask`

- 질문 임베딩으로 `match_store_documents` RPC를 호출합니다.
- RPC와 RLS가 모두 요청 매장의 문서로 범위를 제한합니다.
- 유사도 `0.2` 이상 결과가 없으면 생성 모델을 호출하지 않습니다.
- 답변과 문서 ID, 제목, 종류, 유사도를 반환합니다.

## Not Implemented

- 출퇴근/승인 푸시 알림
- 위치 또는 매장 Wi-Fi 기반 출근 검증
- 서버 측 급여 확정 계산
- RAG 질문 캐시와 PDF 자동 청킹
