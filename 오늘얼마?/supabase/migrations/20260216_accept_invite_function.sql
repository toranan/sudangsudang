-- Accept invite RPC for worker onboarding.
-- Required by app call: rpc("accept_invite", { p_token })

-- 1) Data hygiene for future unique index:
-- Re-point logs to a canonical worker row when duplicate (store_id, user_id) exists,
-- then remove duplicate worker rows.
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

-- 2) Prevent duplicate joins for the same user/store pair.
CREATE UNIQUE INDEX IF NOT EXISTS workers_unique_store_user
ON public.workers (store_id, user_id)
WHERE user_id IS NOT NULL;

-- 3) RPC function used by the app.
-- Drop first so this migration is safe even if an older version exists
-- with a different return type.
DROP FUNCTION IF EXISTS public.accept_invite(TEXT);

CREATE FUNCTION public.accept_invite(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_store_id UUID;
  v_owner_id UUID;
  v_expires_at TIMESTAMPTZ;
  v_profile_name TEXT;
  v_profile_phone TEXT;
  v_worker_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요해요.';
  END IF;

  SELECT i.store_id, i.expires_at, s.owner_id
  INTO v_store_id, v_expires_at, v_owner_id
  FROM public.invites i
  JOIN public.stores s ON s.id = i.store_id
  WHERE i.token = p_token
  LIMIT 1;

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION '유효하지 않은 초대코드예요.';
  END IF;

  IF v_expires_at < NOW() THEN
    RAISE EXCEPTION '만료된 초대코드예요.';
  END IF;

  IF v_owner_id = v_user_id THEN
    RAISE EXCEPTION '내 매장은 초대로 추가할 수 없어요.';
  END IF;

  SELECT name, phone
  INTO v_profile_name, v_profile_phone
  FROM public.profiles
  WHERE id = v_user_id;

  INSERT INTO public.workers (
    user_id,
    store_id,
    name,
    phone,
    hourly_wage,
    is_active
  )
  VALUES (
    v_user_id,
    v_store_id,
    COALESCE(NULLIF(BTRIM(v_profile_name), ''), '알바생'),
    NULLIF(BTRIM(v_profile_phone), ''),
    0,
    TRUE
  )
  ON CONFLICT (store_id, user_id) WHERE user_id IS NOT NULL
  DO UPDATE
  SET
    name = COALESCE(EXCLUDED.name, workers.name),
    phone = COALESCE(EXCLUDED.phone, workers.phone),
    is_active = TRUE
  RETURNING id INTO v_worker_id;

  RETURN jsonb_build_object(
    'ok', true,
    'store_id', v_store_id,
    'worker_id', v_worker_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_invite(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_invite(TEXT) TO authenticated;
