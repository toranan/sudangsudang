-- Store-level payroll defaults with per-worker overrides, plus unpaid break policy.
--
-- Model:
--   stores.default_*            : 매장 기본값
--   workers.*_override (NULL)   : 직원별 예외. NULL이면 매장 기본값을 따른다.
--   workers.hourly_wage, ...    : 실제 적용값(effective). 트리거가 COALESCE(override, 매장 기본값)으로 채운다.
-- Existing readers (app, work_logs snapshot trigger) keep reading the effective columns unchanged.
--
-- Break policy:
--   'none'      : 휴게 없음, 근무시간 전부 유급 (기존 동작과 동일 → 기본값)
--   'statutory' : 법정 기준 (4시간 이상 30분, 8시간 이상 60분) 무급 차감
--   'custom'    : 근무마다 break_minutes 만큼 무급 차감

BEGIN;

-- 1) 매장 기본값 --------------------------------------------------------------

ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS default_hourly_wage NUMERIC,
  ADD COLUMN IF NOT EXISTS default_apply_weekly_allowance BOOLEAN,
  ADD COLUMN IF NOT EXISTS default_apply_night_allowance BOOLEAN,
  ADD COLUMN IF NOT EXISTS default_deduction_type TEXT,
  ADD COLUMN IF NOT EXISTS default_break_policy TEXT,
  ADD COLUMN IF NOT EXISTS default_break_minutes SMALLINT;

-- Seed each store's defaults from the most common terms among its active workers,
-- so most existing workers end up on "매장 기본값" without any pay change.
WITH common AS (
  SELECT
    w.store_id,
    mode() WITHIN GROUP (ORDER BY w.hourly_wage) AS hourly_wage,
    mode() WITHIN GROUP (ORDER BY w.apply_weekly_allowance) AS apply_weekly_allowance,
    mode() WITHIN GROUP (ORDER BY w.apply_night_allowance) AS apply_night_allowance,
    mode() WITHIN GROUP (ORDER BY w.deduction_type) AS deduction_type
  FROM public.workers AS w
  WHERE w.is_active
    AND w.hourly_wage > 0
  GROUP BY w.store_id
)
UPDATE public.stores AS s
SET
  default_hourly_wage = c.hourly_wage,
  default_apply_weekly_allowance = c.apply_weekly_allowance,
  default_apply_night_allowance = c.apply_night_allowance,
  default_deduction_type = c.deduction_type
FROM common AS c
WHERE c.store_id = s.id
  AND s.default_hourly_wage IS NULL;

UPDATE public.stores
SET
  default_hourly_wage = COALESCE(default_hourly_wage, 10320),
  default_apply_weekly_allowance = COALESCE(default_apply_weekly_allowance, FALSE),
  default_apply_night_allowance = COALESCE(default_apply_night_allowance, FALSE),
  default_deduction_type = COALESCE(default_deduction_type, 'withholding_3_3'),
  default_break_policy = COALESCE(default_break_policy, 'none'),
  default_break_minutes = COALESCE(default_break_minutes, 0);

ALTER TABLE public.stores
  ALTER COLUMN default_hourly_wage SET DEFAULT 10320,
  ALTER COLUMN default_hourly_wage SET NOT NULL,
  ALTER COLUMN default_apply_weekly_allowance SET DEFAULT FALSE,
  ALTER COLUMN default_apply_weekly_allowance SET NOT NULL,
  ALTER COLUMN default_apply_night_allowance SET DEFAULT FALSE,
  ALTER COLUMN default_apply_night_allowance SET NOT NULL,
  ALTER COLUMN default_deduction_type SET DEFAULT 'withholding_3_3',
  ALTER COLUMN default_deduction_type SET NOT NULL,
  ALTER COLUMN default_break_policy SET DEFAULT 'none',
  ALTER COLUMN default_break_policy SET NOT NULL,
  ALTER COLUMN default_break_minutes SET DEFAULT 0,
  ALTER COLUMN default_break_minutes SET NOT NULL;

ALTER TABLE public.stores
  DROP CONSTRAINT IF EXISTS stores_default_payroll_check;

ALTER TABLE public.stores
  ADD CONSTRAINT stores_default_payroll_check CHECK (
    default_hourly_wage >= 0
    AND default_deduction_type IN ('withholding_3_3', 'four_insurance')
    AND default_break_policy IN ('none', 'statutory', 'custom')
    AND default_break_minutes BETWEEN 0 AND 240
  );

-- 2) 직원별 예외 + 실제 적용 휴게값 -------------------------------------------

ALTER TABLE public.workers
  ADD COLUMN IF NOT EXISTS hourly_wage_override NUMERIC,
  ADD COLUMN IF NOT EXISTS apply_weekly_allowance_override BOOLEAN,
  ADD COLUMN IF NOT EXISTS apply_night_allowance_override BOOLEAN,
  ADD COLUMN IF NOT EXISTS deduction_type_override TEXT,
  ADD COLUMN IF NOT EXISTS break_policy_override TEXT,
  ADD COLUMN IF NOT EXISTS break_minutes_override SMALLINT,
  ADD COLUMN IF NOT EXISTS break_policy TEXT,
  ADD COLUMN IF NOT EXISTS break_minutes SMALLINT;

-- Workers whose current terms differ from the seeded store default keep them as overrides.
UPDATE public.workers AS w
SET
  hourly_wage_override = CASE
    WHEN w.hourly_wage IS DISTINCT FROM s.default_hourly_wage THEN w.hourly_wage END,
  apply_weekly_allowance_override = CASE
    WHEN w.apply_weekly_allowance IS DISTINCT FROM s.default_apply_weekly_allowance THEN w.apply_weekly_allowance END,
  apply_night_allowance_override = CASE
    WHEN w.apply_night_allowance IS DISTINCT FROM s.default_apply_night_allowance THEN w.apply_night_allowance END,
  deduction_type_override = CASE
    WHEN w.deduction_type IS DISTINCT FROM s.default_deduction_type THEN w.deduction_type END,
  break_policy = s.default_break_policy,
  break_minutes = s.default_break_minutes
FROM public.stores AS s
WHERE s.id = w.store_id;

ALTER TABLE public.workers
  ALTER COLUMN break_policy SET DEFAULT 'none',
  ALTER COLUMN break_policy SET NOT NULL,
  ALTER COLUMN break_minutes SET DEFAULT 0,
  ALTER COLUMN break_minutes SET NOT NULL;

ALTER TABLE public.workers
  DROP CONSTRAINT IF EXISTS workers_payroll_override_check;

ALTER TABLE public.workers
  ADD CONSTRAINT workers_payroll_override_check CHECK (
    (hourly_wage_override IS NULL OR hourly_wage_override >= 0)
    AND (deduction_type_override IS NULL OR deduction_type_override IN ('withholding_3_3', 'four_insurance'))
    AND (break_policy_override IS NULL OR break_policy_override IN ('none', 'statutory', 'custom'))
    AND (break_minutes_override IS NULL OR break_minutes_override BETWEEN 0 AND 240)
    AND break_policy IN ('none', 'statutory', 'custom')
    AND break_minutes BETWEEN 0 AND 240
  );

-- 3) 실제 적용값 동기화 ---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resolve_worker_payroll_terms()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s public.stores%ROWTYPE;
BEGIN
  -- Older app builds write the effective columns directly. Treat such a write
  -- (effective value changed while its override did not) as setting an override.
  IF TG_OP = 'UPDATE' THEN
    IF NEW.hourly_wage IS DISTINCT FROM OLD.hourly_wage
       AND NEW.hourly_wage_override IS NOT DISTINCT FROM OLD.hourly_wage_override THEN
      NEW.hourly_wage_override := NEW.hourly_wage;
    END IF;
    IF NEW.apply_weekly_allowance IS DISTINCT FROM OLD.apply_weekly_allowance
       AND NEW.apply_weekly_allowance_override IS NOT DISTINCT FROM OLD.apply_weekly_allowance_override THEN
      NEW.apply_weekly_allowance_override := NEW.apply_weekly_allowance;
    END IF;
    IF NEW.apply_night_allowance IS DISTINCT FROM OLD.apply_night_allowance
       AND NEW.apply_night_allowance_override IS NOT DISTINCT FROM OLD.apply_night_allowance_override THEN
      NEW.apply_night_allowance_override := NEW.apply_night_allowance;
    END IF;
    IF NEW.deduction_type IS DISTINCT FROM OLD.deduction_type
       AND NEW.deduction_type_override IS NOT DISTINCT FROM OLD.deduction_type_override THEN
      NEW.deduction_type_override := NEW.deduction_type;
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    -- A positive wage sent on insert by an older build is an explicit choice.
    IF NEW.hourly_wage_override IS NULL AND COALESCE(NEW.hourly_wage, 0) > 0 THEN
      NEW.hourly_wage_override := NEW.hourly_wage;
    END IF;
  END IF;

  SELECT * INTO s FROM public.stores WHERE id = NEW.store_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Overrides equal to the store default collapse back to "매장 기본값".
  IF NEW.hourly_wage_override = s.default_hourly_wage THEN NEW.hourly_wage_override := NULL; END IF;
  IF NEW.apply_weekly_allowance_override = s.default_apply_weekly_allowance THEN NEW.apply_weekly_allowance_override := NULL; END IF;
  IF NEW.apply_night_allowance_override = s.default_apply_night_allowance THEN NEW.apply_night_allowance_override := NULL; END IF;
  IF NEW.deduction_type_override = s.default_deduction_type THEN NEW.deduction_type_override := NULL; END IF;

  NEW.hourly_wage := COALESCE(NEW.hourly_wage_override, s.default_hourly_wage);
  NEW.apply_weekly_allowance := COALESCE(NEW.apply_weekly_allowance_override, s.default_apply_weekly_allowance);
  NEW.apply_night_allowance := COALESCE(NEW.apply_night_allowance_override, s.default_apply_night_allowance);
  NEW.deduction_type := COALESCE(NEW.deduction_type_override, s.default_deduction_type);
  NEW.break_policy := COALESCE(NEW.break_policy_override, s.default_break_policy);
  NEW.break_minutes := CASE
    WHEN NEW.break_policy = 'custom'
      THEN COALESCE(NEW.break_minutes_override, s.default_break_minutes)
    ELSE 0
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resolve_worker_payroll_terms_trigger ON public.workers;

CREATE TRIGGER resolve_worker_payroll_terms_trigger
BEFORE INSERT OR UPDATE ON public.workers
FOR EACH ROW
EXECUTE FUNCTION public.resolve_worker_payroll_terms();

-- When a store default changes, re-resolve the workers that follow it.
CREATE OR REPLACE FUNCTION public.propagate_store_payroll_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Touch override columns only (no-op assignment) so the workers trigger
  -- recomputes effective values without mistaking it for a legacy write.
  UPDATE public.workers
  SET hourly_wage_override = hourly_wage_override
  WHERE store_id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS propagate_store_payroll_defaults_trigger ON public.stores;

CREATE TRIGGER propagate_store_payroll_defaults_trigger
AFTER UPDATE OF
  default_hourly_wage,
  default_apply_weekly_allowance,
  default_apply_night_allowance,
  default_deduction_type,
  default_break_policy,
  default_break_minutes
ON public.stores
FOR EACH ROW
EXECUTE FUNCTION public.propagate_store_payroll_defaults();

-- 4) 근무 기록 스냅샷에 휴게 포함 ----------------------------------------------

ALTER TABLE public.work_logs
  ADD COLUMN IF NOT EXISTS applied_break_policy TEXT,
  ADD COLUMN IF NOT EXISTS applied_break_minutes SMALLINT;

-- Existing logs were all paid in full, which is exactly 'none'.
UPDATE public.work_logs
SET applied_break_policy = 'none', applied_break_minutes = 0
WHERE applied_break_policy IS NULL OR applied_break_minutes IS NULL;

ALTER TABLE public.work_logs
  ALTER COLUMN applied_break_policy SET NOT NULL,
  ALTER COLUMN applied_break_minutes SET NOT NULL;

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
    NEW.applied_break_policy := OLD.applied_break_policy;
    NEW.applied_break_minutes := OLD.applied_break_minutes;
    RETURN NEW;
  END IF;

  SELECT
    GREATEST(COALESCE(w.hourly_wage, 0), 0),
    COALESCE(w.apply_night_allowance, FALSE),
    COALESCE(w.break_policy, 'none'),
    COALESCE(w.break_minutes, 0)
  INTO
    NEW.applied_hourly_wage,
    NEW.applied_night_allowance,
    NEW.applied_break_policy,
    NEW.applied_break_minutes
  FROM public.workers AS w
  WHERE w.id = NEW.worker_id
    AND w.store_id = NEW.store_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'worker does not belong to the selected store';
  END IF;

  RETURN NEW;
END;
$$;

-- 5) 사장님 전용 메모 -----------------------------------------------------------
-- Workers can SELECT their own workers row, so the memo lives in a separate
-- owner-only table instead of a workers column.

CREATE TABLE IF NOT EXISTS public.worker_notes (
  worker_id UUID PRIMARY KEY REFERENCES public.workers(id) ON DELETE CASCADE,
  store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  body TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.worker_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage notes in their stores" ON public.worker_notes;

CREATE POLICY "Owners manage notes in their stores"
ON public.worker_notes FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.stores
    WHERE stores.id = worker_notes.store_id
      AND stores.owner_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.stores
    JOIN public.workers ON workers.store_id = stores.id
    WHERE stores.id = worker_notes.store_id
      AND workers.id = worker_notes.worker_id
      AND stores.owner_id = auth.uid()
  )
);

-- Re-resolve every worker once so effective columns match the new rules.
UPDATE public.workers SET hourly_wage_override = hourly_wage_override;

COMMIT;
