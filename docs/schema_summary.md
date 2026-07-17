# Schema Summary

> 기준: `docs/supabase_schema.sql` + `supabase/migrations/*.sql`, 2026-07-15

## Core

| Table | Purpose | Key columns |
|---|---|---|
| `profiles` | 인증 사용자 프로필과 역할 | `id`, `email`, `name`, `phone`, `role`, `kakao_id` |
| `stores` | 사장님 소유 매장 | `id`, `owner_id`, `name`, `address`, `is_personal` |
| `workers` | 사용자와 매장의 근로 연결/현재 급여 설정 | `id`, `store_id`, `user_id`, `hourly_wage`, `apply_weekly_allowance`, `apply_night_allowance`, `deduction_type`, `payday`, `is_active` |
| `work_logs` | 출퇴근과 승인 기록 | `id`, `store_id`, `worker_id`, `check_in_at`, `check_out_at`, `status`, `applied_hourly_wage`, `applied_night_allowance`, `approved_by`, `approved_at` |
| `invites` | 매장 초대 토큰 | `id`, `store_id`, `token`, `expires_at` |

## Scheduling And Evaluation

| Table | Purpose |
|---|---|
| `schedule_templates` | 매장별 반복 주간 근무 설정 |
| `schedule_entries` | 날짜별 근무 일정과 상태 |
| `worker_owner_ratings` | 매장/직원/사장님 조합의 평가 |

## Store Knowledge

| Table | Purpose | Key columns |
|---|---|---|
| `store_documents` | 공지/매뉴얼 원문과 검색 벡터 | `store_id`, `title`, `content`, `document_type`, `is_pinned`, `embedding vector(1536)`, `metadata` |

`match_store_documents` RPC는 `store_id`로 문서를 제한하고 cosine similarity 순서로 최대 10개를 반환합니다. 사장님은 소유 매장 문서를 관리하고, 활성 알바생은 소속 매장 문서만 조회하도록 RLS를 적용합니다.

## Integrity Rules

- `work_logs.check_out_at >= check_in_at`
- `work_logs` 생성 시 현재 시급과 야간수당 적용 여부를 저장하고, 이후 수정 시 유지
- 매장/직원별 열린 근무 기록은 최대 1개
- 매장/사용자별 활성 연결 중복 방지
- `workers.payday`는 1~31
- 스케줄과 평가는 매장/사용자 조합별 중복 제약 적용

## Payroll Snapshot

`work_logs` 생성 시 `workers`의 시급과 야간수당 적용 여부를 스냅샷으로 저장합니다. 이후 시급을 바꿔도 기존 근무 기록은 생성 당시 기준으로 계산됩니다. 공제와 주휴수당은 아직 현재 설정을 사용하는 예상치이며, 세부 판단은 [ADR 0002](adr/0002-payroll-snapshot.md)에 기록합니다.
