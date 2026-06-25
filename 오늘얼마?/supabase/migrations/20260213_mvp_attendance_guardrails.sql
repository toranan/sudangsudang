-- MVP attendance guardrails
-- Goal:
-- 1) Allow multiple shifts per day.
-- 2) Prevent more than one "open" shift per (store_id, worker_id) at the same time.

-- If duplicate open logs already exist, keep the latest open log and close older ones at check-in time
-- so they contribute 0 minutes instead of inflating payouts.
WITH ranked_open AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY store_id, worker_id
      ORDER BY check_in_at DESC, id DESC
    ) AS rn
  FROM public.work_logs
  WHERE check_out_at IS NULL
)
UPDATE public.work_logs wl
SET check_out_at = wl.check_in_at
FROM ranked_open ro
WHERE wl.id = ro.id
  AND ro.rn > 1;

-- Enforce one open log per worker/store pair at DB level.
CREATE UNIQUE INDEX IF NOT EXISTS work_logs_one_open_shift_per_worker_store
ON public.work_logs (store_id, worker_id)
WHERE check_out_at IS NULL;

-- Basic temporal integrity.
ALTER TABLE public.work_logs
  DROP CONSTRAINT IF EXISTS work_logs_checkout_after_checkin;

ALTER TABLE public.work_logs
  ADD CONSTRAINT work_logs_checkout_after_checkin
  CHECK (check_out_at IS NULL OR check_out_at >= check_in_at);
