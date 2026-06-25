-- Schedule management for owner calendar / weekly templates

CREATE TABLE IF NOT EXISTS public.schedule_templates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    store_id UUID REFERENCES public.stores(id) ON DELETE CASCADE NOT NULL,
    worker_id UUID REFERENCES public.workers(id) ON DELETE CASCADE NOT NULL,
    weekday SMALLINT NOT NULL CHECK (weekday >= 0 AND weekday <= 6), -- 0: Sun ... 6: Sat
    check_in_time TIME NOT NULL,
    check_out_time TIME,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS schedule_templates_store_idx
ON public.schedule_templates (store_id);

CREATE INDEX IF NOT EXISTS schedule_templates_store_weekday_idx
ON public.schedule_templates (store_id, weekday)
WHERE is_active = TRUE;

CREATE TABLE IF NOT EXISTS public.schedule_entries (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    store_id UUID REFERENCES public.stores(id) ON DELETE CASCADE NOT NULL,
    worker_id UUID REFERENCES public.workers(id) ON DELETE CASCADE NOT NULL,
    work_date DATE NOT NULL,
    check_in_time TIME NOT NULL,
    check_out_time TIME,
    source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'template')),
    template_id UUID REFERENCES public.schedule_templates(id) ON DELETE SET NULL,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS schedule_entries_store_date_idx
ON public.schedule_entries (store_id, work_date);

CREATE INDEX IF NOT EXISTS schedule_entries_worker_date_idx
ON public.schedule_entries (worker_id, work_date);

-- Keep one generated row per template/day so auto generation stays idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS schedule_entries_template_day_unique
ON public.schedule_entries (store_id, template_id, work_date)
WHERE template_id IS NOT NULL;

ALTER TABLE public.schedule_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_entries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'schedule_templates'
          AND policyname = 'Owners can manage schedule templates for own stores'
    ) THEN
        CREATE POLICY "Owners can manage schedule templates for own stores"
        ON public.schedule_templates FOR ALL USING (
            EXISTS (
                SELECT 1
                FROM public.stores
                WHERE stores.id = schedule_templates.store_id
                  AND stores.owner_id = auth.uid()
            )
        ) WITH CHECK (
            EXISTS (
                SELECT 1
                FROM public.stores
                WHERE stores.id = schedule_templates.store_id
                  AND stores.owner_id = auth.uid()
            )
        );
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'schedule_entries'
          AND policyname = 'Owners can manage schedule entries for own stores'
    ) THEN
        CREATE POLICY "Owners can manage schedule entries for own stores"
        ON public.schedule_entries FOR ALL USING (
            EXISTS (
                SELECT 1
                FROM public.stores
                WHERE stores.id = schedule_entries.store_id
                  AND stores.owner_id = auth.uid()
            )
        ) WITH CHECK (
            EXISTS (
                SELECT 1
                FROM public.stores
                WHERE stores.id = schedule_entries.store_id
                  AND stores.owner_id = auth.uid()
            )
        );
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'schedule_entries'
          AND policyname = 'Workers can view own schedule entries'
    ) THEN
        CREATE POLICY "Workers can view own schedule entries"
        ON public.schedule_entries FOR SELECT USING (
            EXISTS (
                SELECT 1
                FROM public.workers
                WHERE workers.id = schedule_entries.worker_id
                  AND workers.user_id = auth.uid()
            )
        );
    END IF;
END
$$;
