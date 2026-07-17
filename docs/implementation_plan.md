# Implementation Plan - 수당수당

## Goal Description
Develop an iOS application for store owners and part-time workers to manage attendance and calculate wages.
The app generates QR/Links for invitations, allows workers to check in/out, and owners to approve logs for automatic time/wage calculation.
**Key Style**: Clean, friendly UI (Toss-like).
**Tech Stack**: iOS (SwiftUI), Supabase (Auth, DB, Realtime).

## User Review Required
> [!IMPORTANT]
> **Supabase Setup**: Need to ensure Supabase project is created and credentials (URL, Key) are available.
> **Apple Developer Account**: Required for Push Notifications (APNs) configuration.

## Proposed Changes

### Database Schema (Supabase)

#### [NEW] Tables
- **profiles**: Extended user data (synced with Auth). `id`, `role` (owner/worker), `created_at`.
- **stores**: `id`, `name`, `owner_id` (FK profiles), `address`, `created_at`.
- **workers**: `id`, `user_id` (FK profiles), `store_id` (FK stores), `name`, `phone`, `hourly_wage`, `is_active`.
- **invites**: `id`, `store_id` (FK stores), `token`, `qr_url`, `expires_at`, `created_at`.
- **work_logs**: `id`, `store_id`, `worker_id`, `check_in_at`, `check_out_at`, `status` (pending/approved/rejected), `approved_by`, `updated_at`.

### iOS App Architecture

#### [NEW] Project Structure
- **App**: `HowMuchTodayApp.swift` (Main entry, Supabase init)
- **Features**:
    - **Auth**: Login/SignUp View, Onboarding.
    - **Owner**:
        - `StoreHomeView`: Dashboard.
        - `WorkerManagementView`: List of workers, Send Invite.
        - `ApprovalView`: List of pending work logs.
        - `StatsView`: Weekly/Monthly summary.
    - **Worker**:
        - `WorkerHomeView`: Check-in/out button, Current status.
        - `MyHistoryView`: List of own logs and status.
- **Services**:
    - `SupabaseManager`: Wrapper for Supabase client.
    - `AuthService`: Handle sign-in/up.
    - `StoreService`: CRUD for stores and invites.
    - `AttendanceService`: Check-in/out logic, approvals.

### UI/UX Design (Toss Style)
- **Typography**: Big bold headers, clear readability (Pretendard or system font).
- **Colors**: Blue/Primary for actions, Light Gray for backgrounds, clearly distinguishing states (Approved=Green, Pending=Orange).
- **Interactions**: Smooth transitions, bottom sheets for details, haptic feedback on buttons.

## Verification Plan

### Manual Verification
1.  **Owner Flow**:
    - Sign up -> Create Store -> Generate Invite.
    - Approve specific work log -> Verify total time calculation.
2.  **Worker Flow**:
    - Scan QR (Simulated via Deep Link) -> Join Store.
    - Check In -> Owner receives 'Pending' log.
    - Check Out -> Log updates -> Owner approves.
3.  **Exception Cases**:
    - Verify "Already checked in" prevents double check-in.
    - Verify "Forgot to check out" handling (manual edit request - Phase 2, but basic handling in MVP).
