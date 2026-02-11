# API & Permission Rules

## Authentication & Roles
*   **Auth Provider**: Supabase Auth (Email/Password or Social).
*   **Roles**: `owner`, `worker`.
    *   Stored in `public.profiles`.
    *   Determined at Signup/Onboarding.

## Permission Matrix

| Resource | Action | Owner | Worker | Public |
| :--- | :--- | :--- | :--- | :--- |
| **Store** | Create | ✅ | ❌ | ❌ |
| | Read | ✅ (Own) | ✅ (Joined) | ❌ |
| | Update | ✅ (Own) | ❌ | ❌ |
| **Worker** | Invite | ✅ | ❌ | ❌ |
| | Read | ✅ (Global List of own store) | ✅ (Self) | ❌ |
| | Kick | ✅ | ❌ | ❌ |
| **WorkLog** | Create (Check-in) | ❌ | ✅ | ❌ |
| | Update (Check-out) | ❌ | ✅ | ❌ |
| | Approve/Reject | ✅ | ❌ | ❌ |
| | Read | ✅ (All in store) | ✅ (Self) | ❌ |

## Business Logic Rules

### 1. Invitation & Onboarding
*   **Token Generation**: Owner generates a unique JWT or random string token synced to `store_id`.
*   **Expiration**: Tokens expire after 24-48 hours.
*   **Joining**:
    *   Worker scans QR -> Opens App with Deep Link (`howmuch://invite?token=xyz`).
    *   App queries `invites` table.
    *   If valid, adds entry to `workers` table linking `auth.uid()` to `store_id`.

### 2. Attendance (Check-in/Check-out)
*   **Check-in**:
    *   Worker taps "Check-in".
    *   App verifies geolocation (optional MVP) or WiFi.
    *   Creates `work_log` with `check_in_at = NOW()`, `status = pending`.
    *   **Constraint**: Cannot check-in if there is already an open log (where `check_out_at` is NULL).
*   **Check-out**:
    *   Worker taps "Check-out".
    *   Updates active `work_log` set `check_out_at = NOW()`.
    *   Status remains `pending` until Owner approves.

### 3. Approval System (Owner)
*   Owner sees list of `pending` logs.
*   Action: `Approve` -> Status becomes `approved`.
    *   Only `approved` logs constitute "Payable Hours".
*   Action: `Reject` -> Log kept but ignored for calc.
*   Action: `Edit` -> Owner can modify time before approving (e.g., if worker forgot to clock out).

### 4. Notifications (Push)
*   **Triggers**:
    *   Worker Check-in -> Notify Owner ("OOO님이 출근했습니다").
    *   Worker Check-out -> Notify Owner ("OOO님이 퇴근했습니다").
    *   Owner Approve -> Notify Worker ("근무가 승인되었습니다").
*   **Implementation**: Supabase Edge Functions with FCM/APNs.

## Security Considerations
*   **RLS (Row Level Security)**: Strict policies in `supabase_schema.sql` enforce data isolation.
*   **Deep Links**: Validated on server-side (or via RLS lookup) to prevent unauthorized joining.
