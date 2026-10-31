-- 결근 기록. 사장님이 "이 날 이 알바는 결근"이라고 확정한 것을 남긴다.
-- 출근 기록이 없다는 것만으로는 결근인지 쉬는 날인지 구분할 수 없어서 따로 둔다.
-- 스케줄 자동 기록(다음 단계)은 결근으로 확정된 날을 건너뛴다.

CREATE TABLE IF NOT EXISTS public.work_absences (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    worker_id UUID NOT NULL REFERENCES public.workers(id) ON DELETE CASCADE,
    work_date DATE NOT NULL,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (worker_id, work_date)
);

CREATE INDEX IF NOT EXISTS work_absences_store_date_idx
ON public.work_absences (store_id, work_date);

ALTER TABLE public.work_absences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage absences for own stores" ON public.work_absences;
CREATE POLICY "Owners manage absences for own stores"
ON public.work_absences FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.stores
        WHERE stores.id = work_absences.store_id
          AND stores.owner_id = auth.uid()
    )
) WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.stores
        WHERE stores.id = work_absences.store_id
          AND stores.owner_id = auth.uid()
    )
    -- 다른 매장 알바를 결근 처리하지 못하게 한다.
    AND EXISTS (
        SELECT 1 FROM public.workers
        WHERE workers.id = work_absences.worker_id
          AND workers.store_id = work_absences.store_id
    )
);

DROP POLICY IF EXISTS "Workers can view own absences" ON public.work_absences;
CREATE POLICY "Workers can view own absences"
ON public.work_absences FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.workers
        WHERE workers.id = work_absences.worker_id
          AND workers.user_id = auth.uid()
    )
);
