-- 주휴수당 지급 여부도 시급·야간수당·휴게처럼 근무 기록에 스냅샷으로 남긴다.
-- 전에는 주휴수당을 화면마다 직원의 "현재" 설정으로 계산해서, 설정을 끄거나 시급을 바꾸면
-- 이미 지난달 주휴수당까지 바뀌어 보였다. 이제 각 주는 그 주 근무에 남은 설정으로 계산한다.

-- 1) 칸 추가
ALTER TABLE public.work_logs
  ADD COLUMN IF NOT EXISTS applied_weekly_allowance BOOLEAN;

-- 2) 기존 기록은 지금 설정으로 채운다(지금 화면에 보이는 금액이 그대로 유지된다).
--    트리거를 바꾸기 전에 채워야 한다. 새 트리거는 UPDATE 때 이 값을 이전 값으로 되돌리기 때문.
UPDATE public.work_logs AS wl
SET applied_weekly_allowance = COALESCE(w.apply_weekly_allowance, FALSE)
FROM public.workers AS w
WHERE w.id = wl.worker_id
  AND wl.applied_weekly_allowance IS NULL;

-- 3) 스냅샷 트리거에 주휴 설정을 더한다. 나머지는 20261101과 같다.
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
     AND NEW.store_id IS NOT DISTINCT FROM OLD.store_id
     AND COALESCE(current_setting('app.reapply_payroll_terms', true), '') <> 'on' THEN
    NEW.applied_hourly_wage := OLD.applied_hourly_wage;
    NEW.applied_night_allowance := OLD.applied_night_allowance;
    NEW.applied_break_policy := OLD.applied_break_policy;
    NEW.applied_break_minutes := OLD.applied_break_minutes;
    NEW.applied_weekly_allowance := OLD.applied_weekly_allowance;
    RETURN NEW;
  END IF;

  SELECT
    GREATEST(COALESCE(w.hourly_wage, 0), 0),
    COALESCE(w.apply_night_allowance, FALSE),
    COALESCE(w.break_policy, 'none'),
    COALESCE(w.break_minutes, 0),
    COALESCE(w.apply_weekly_allowance, FALSE)
  INTO
    NEW.applied_hourly_wage,
    NEW.applied_night_allowance,
    NEW.applied_break_policy,
    NEW.applied_break_minutes,
    NEW.applied_weekly_allowance
  FROM public.workers AS w
  WHERE w.id = NEW.worker_id
    AND w.store_id = NEW.store_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'worker does not belong to the selected store';
  END IF;

  RETURN NEW;
END;
$$;

-- reapply_payroll_terms_this_month는 트리거로 스냅샷을 다시 찍으므로 고칠 것이 없다.
-- 이번 달 근무에 다시 적용하면 주휴 설정도 함께 다시 적용된다.
