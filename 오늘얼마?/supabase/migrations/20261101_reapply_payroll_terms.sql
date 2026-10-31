-- 급여 설정(시급, 야간수당, 무급 휴게)을 바꾼 뒤, 이번 달에 이미 기록된 근무에도 다시 적용한다.
-- 근무 기록은 생길 때의 설정을 스냅샷으로 고정하므로(set_work_log_payroll_snapshot),
-- 사장님이 고를 때만 이 함수로 이번 달 기록의 스냅샷을 현재 설정으로 다시 찍는다.

-- 1) 스냅샷 트리거: 재적용 중일 때만 기존 스냅샷을 지키지 않고 현재 설정으로 다시 찍는다.
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

-- 2) 이번 달(한국 시간) 근무 기록에 현재 급여 설정을 다시 적용한다.
--    p_worker_id가 NULL이면 매장의 모든 직원. 매장 사장님만 부를 수 있다. 바뀐 기록 수를 돌려준다.
CREATE OR REPLACE FUNCTION public.reapply_payroll_terms_this_month(
  p_store_id UUID,
  p_worker_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  month_start TIMESTAMPTZ;
  updated_count INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.stores
    WHERE stores.id = p_store_id
      AND stores.owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'only the store owner can reapply payroll terms';
  END IF;

  month_start := date_trunc('month', NOW() AT TIME ZONE 'Asia/Seoul') AT TIME ZONE 'Asia/Seoul';

  PERFORM set_config('app.reapply_payroll_terms', 'on', true);

  UPDATE public.work_logs
  SET worker_id = worker_id
  WHERE store_id = p_store_id
    AND (p_worker_id IS NULL OR worker_id = p_worker_id)
    AND check_in_at >= month_start;
  GET DIAGNOSTICS updated_count = ROW_COUNT;

  PERFORM set_config('app.reapply_payroll_terms', 'off', true);

  RETURN updated_count;
END;
$$;

REVOKE ALL ON FUNCTION public.reapply_payroll_terms_this_month(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reapply_payroll_terms_this_month(UUID, UUID) TO authenticated;
