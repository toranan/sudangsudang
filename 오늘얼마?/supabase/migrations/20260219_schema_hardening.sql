-- Core schema hardening for production safety.
-- 1) Ensure stores.is_personal exists for app queries.
-- 2) Enforce non-null work_logs.status to prevent decode failures.
-- 3) Keep workers unique per (store_id, user_id).
-- 4) Tighten worker write policy on work_logs.
-- 5) Provide safe worker self-retirement RPC.

-- 1) stores.is_personal
ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS is_personal BOOLEAN;

UPDATE public.stores
SET is_personal = FALSE
WHERE is_personal IS NULL;

ALTER TABLE public.stores
  ALTER COLUMN is_personal SET DEFAULT FALSE;

ALTER TABLE public.stores
  ALTER COLUMN is_personal SET NOT NULL;

-- 2) work_logs.status hygiene
UPDATE public.work_logs
SET status = 'pending'
WHERE status IS NULL;

ALTER TABLE public.work_logs
  ALTER COLUMN status SET DEFAULT 'pending';

ALTER TABLE public.work_logs
  ALTER COLUMN status SET NOT NULL;

-- 3) workers uniqueness hygiene + index
WITH ranked AS (
  SELECT
    id,
    store_id,
    user_id,
    FIRST_VALUE(id) OVER (
      PARTITION BY store_id, user_id
      ORDER BY joined_at ASC, id ASC
    ) AS keeper_id
  FROM public.workers
  WHERE user_id IS NOT NULL
),
repoint_logs AS (
  UPDATE public.work_logs wl
  SET worker_id = r.keeper_id
  FROM ranked r
  WHERE wl.worker_id = r.id
    AND r.id <> r.keeper_id
  RETURNING wl.id
)
DELETE FROM public.workers w
USING ranked r
WHERE w.id = r.id
  AND r.id <> r.keeper_id;

CREATE UNIQUE INDEX IF NOT EXISTS workers_unique_store_user
ON public.workers (store_id, user_id)
WHERE user_id IS NOT NULL;

-- 4) Tighten worker policies on work_logs.
DROP POLICY IF EXISTS "Workers can insert/update their own logs (Check-in/out)" ON public.work_logs;
DROP POLICY IF EXISTS "Workers can update their own logs" ON public.work_logs;
DROP POLICY IF EXISTS "Workers can insert their own open log" ON public.work_logs;
DROP POLICY IF EXISTS "Workers can checkout their own open log" ON public.work_logs;

CREATE POLICY "Workers can insert their own open log"
ON public.work_logs FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.workers w
    WHERE w.id = work_logs.worker_id
      AND w.user_id = auth.uid()
      AND w.store_id = work_logs.store_id
  )
  AND work_logs.check_out_at IS NULL
  AND COALESCE(work_logs.status, 'pending') = 'pending'
  AND work_logs.approved_by IS NULL
  AND work_logs.approved_at IS NULL
);

CREATE POLICY "Workers can checkout their own open log"
ON public.work_logs FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.workers w
    WHERE w.id = work_logs.worker_id
      AND w.user_id = auth.uid()
      AND w.store_id = work_logs.store_id
  )
  AND work_logs.check_out_at IS NULL
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.workers w
    WHERE w.id = work_logs.worker_id
      AND w.user_id = auth.uid()
      AND w.store_id = work_logs.store_id
  )
  AND work_logs.check_out_at IS NOT NULL
  AND COALESCE(work_logs.status, 'pending') = 'pending'
  AND work_logs.approved_by IS NULL
  AND work_logs.approved_at IS NULL
);

-- 5) Safe worker self-retirement endpoint.
DROP FUNCTION IF EXISTS public.retire_worker_link(UUID);

CREATE FUNCTION public.retire_worker_link(p_worker_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_updated UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요해요.';
  END IF;

  UPDATE public.workers
  SET is_active = FALSE
  WHERE id = p_worker_id
    AND user_id = v_user_id
    AND is_active = TRUE
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found_or_forbidden');
  END IF;

  RETURN jsonb_build_object('ok', true, 'worker_id', v_updated);
END;
$$;

REVOKE ALL ON FUNCTION public.retire_worker_link(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.retire_worker_link(UUID) TO authenticated;
