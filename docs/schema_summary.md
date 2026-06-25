# Schema Summary

## profiles
- id (uuid, PK, FK to auth.users.id)
- email (text)
- name (text)
- phone (text)
- role (text)
- created_at (timestamptz)
- updated_at (timestamptz)
- kakao_id (text)

## stores
- id (uuid, PK)
- owner_id (uuid, FK to profiles.id)
- name (text)
- address (text)
- created_at (timestamptz)
- is_personal (bool)

## workers
- id (uuid, PK)
- user_id (uuid, FK to profiles.id)
- store_id (uuid, FK to stores.id)
- name (text)
- phone (text)
- hourly_wage (numeric)
- apply_weekly_allowance (bool)
- deduction_type (text, 'withholding_3_3' | 'four_insurance')
- apply_night_allowance (bool)
- payday (smallint, 1..31)
- is_active (bool)
- joined_at (timestamptz)

## work_logs
- id (uuid, PK)
- store_id (uuid, FK to stores.id)
- worker_id (uuid, FK to workers.id)
- check_in_at (timestamptz)
- check_out_at (timestamptz)
- status (text)
- approved_by (uuid)
- approved_at (timestamptz)
- created_at (timestamptz)
- updated_at (timestamptz)

## invites
- id (uuid, PK)
- store_id (uuid, FK to stores.id)
- token (text)
- expires_at (timestamptz)
- created_at (timestamptz)
