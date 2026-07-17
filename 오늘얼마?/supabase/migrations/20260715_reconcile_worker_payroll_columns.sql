-- Reconcile environments where the 20260220 migration was recorded before
-- the payroll columns were added to its local SQL file, then snapshot the
-- applied wage terms on every work log.

BEGIN;

ALTER TABLE public.workers
  ADD COLUMN IF NOT EXISTS apply_night_allowance BOOLEAN;

UPDATE public.workers
SET apply_night_allowance = FALSE
WHERE apply_night_allowance IS NULL;

ALTER TABLE public.workers
  ALTER COLUMN apply_night_allowance SET DEFAULT FALSE,
  ALTER COLUMN apply_night_allowance SET NOT NULL;

ALTER TABLE public.workers
  ADD COLUMN IF NOT EXISTS payday SMALLINT;

UPDATE public.workers
SET payday = 10
WHERE payday IS NULL
   OR payday < 1
   OR payday > 31;

ALTER TABLE public.workers
  ALTER COLUMN payday SET DEFAULT 10,
  ALTER COLUMN payday SET NOT NULL;

ALTER TABLE public.workers
  DROP CONSTRAINT IF EXISTS workers_payday_range;

ALTER TABLE public.workers
  ADD CONSTRAINT workers_payday_range CHECK (payday BETWEEN 1 AND 31);

ALTER TABLE public.work_logs
  ADD COLUMN IF NOT EXISTS applied_hourly_wage NUMERIC,
  ADD COLUMN IF NOT EXISTS applied_night_allowance BOOLEAN;

-- Historical terms cannot be reconstructed if wages changed before this
-- migration. Use the current worker terms as the one-time baseline.
UPDATE public.work_logs AS wl
SET
  applied_hourly_wage = GREATEST(COALESCE(w.hourly_wage, 0), 0),
  applied_night_allowance = COALESCE(w.apply_night_allowance, FALSE)
FROM public.workers AS w
WHERE w.id = wl.worker_id
  AND w.store_id = wl.store_id
  AND (
    wl.applied_hourly_wage IS NULL
    OR wl.applied_night_allowance IS NULL
  );

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.work_logs
    WHERE applied_hourly_wage IS NULL
       OR applied_night_allowance IS NULL
  ) THEN
    RAISE EXCEPTION 'work_logs payroll snapshot backfill failed';
  END IF;
END
$$;

ALTER TABLE public.work_logs
  ALTER COLUMN applied_hourly_wage SET NOT NULL,
  ALTER COLUMN applied_night_allowance SET NOT NULL;

ALTER TABLE public.work_logs
  DROP CONSTRAINT IF EXISTS work_logs_applied_hourly_wage_nonnegative;

ALTER TABLE public.work_logs
  ADD CONSTRAINT work_logs_applied_hourly_wage_nonnegative
  CHECK (applied_hourly_wage >= 0);

CREATE OR REPLACE FUNCTION public.set_work_log_payroll_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Preserve the original snapshot when an existing log is approved or edited.
  IF TG_OP = 'UPDATE'
     AND NEW.worker_id IS NOT DISTINCT FROM OLD.worker_id
     AND NEW.store_id IS NOT DISTINCT FROM OLD.store_id THEN
    NEW.applied_hourly_wage := OLD.applied_hourly_wage;
    NEW.applied_night_allowance := OLD.applied_night_allowance;
    RETURN NEW;
  END IF;

  SELECT
    GREATEST(COALESCE(w.hourly_wage, 0), 0),
    COALESCE(w.apply_night_allowance, FALSE)
  INTO
    NEW.applied_hourly_wage,
    NEW.applied_night_allowance
  FROM public.workers AS w
  WHERE w.id = NEW.worker_id
    AND w.store_id = NEW.store_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'worker does not belong to the selected store';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_work_log_payroll_snapshot_trigger
ON public.work_logs;

CREATE TRIGGER set_work_log_payroll_snapshot_trigger
BEFORE INSERT OR UPDATE ON public.work_logs
FOR EACH ROW
EXECUTE FUNCTION public.set_work_log_payroll_snapshot();

COMMENT ON COLUMN public.work_logs.applied_hourly_wage IS
  'Hourly wage copied from workers when the work log is created.';

COMMENT ON COLUMN public.work_logs.applied_night_allowance IS
  'Night allowance flag copied from workers when the work log is created.';

COMMIT;
