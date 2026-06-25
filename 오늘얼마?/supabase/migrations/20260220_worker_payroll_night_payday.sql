-- Worker payroll settings extension:
-- 1) Owner-managed night allowance flag for linked stores
-- 2) Owner-managed payday day-of-month

ALTER TABLE public.workers
  ADD COLUMN IF NOT EXISTS apply_night_allowance BOOLEAN;

UPDATE public.workers
SET apply_night_allowance = FALSE
WHERE apply_night_allowance IS NULL;

ALTER TABLE public.workers
  ALTER COLUMN apply_night_allowance SET DEFAULT FALSE;

ALTER TABLE public.workers
  ALTER COLUMN apply_night_allowance SET NOT NULL;

ALTER TABLE public.workers
  ADD COLUMN IF NOT EXISTS payday SMALLINT;

UPDATE public.workers
SET payday = 10
WHERE payday IS NULL
   OR payday < 1
   OR payday > 31;

ALTER TABLE public.workers
  ALTER COLUMN payday SET DEFAULT 10;

ALTER TABLE public.workers
  ALTER COLUMN payday SET NOT NULL;

ALTER TABLE public.workers
  DROP CONSTRAINT IF EXISTS workers_payday_range;

ALTER TABLE public.workers
  ADD CONSTRAINT workers_payday_range CHECK (payday BETWEEN 1 AND 31);
