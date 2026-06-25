-- Owner sincerity rating used for worker evaluation mark.

CREATE TABLE IF NOT EXISTS public.worker_owner_ratings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    store_id UUID REFERENCES public.stores(id) ON DELETE CASCADE NOT NULL,
    worker_id UUID REFERENCES public.workers(id) ON DELETE CASCADE NOT NULL,
    owner_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    rating SMALLINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (store_id, worker_id, owner_id)
);

CREATE INDEX IF NOT EXISTS worker_owner_ratings_store_worker_idx
ON public.worker_owner_ratings (store_id, worker_id);

CREATE INDEX IF NOT EXISTS worker_owner_ratings_owner_idx
ON public.worker_owner_ratings (owner_id);

ALTER TABLE public.worker_owner_ratings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'worker_owner_ratings'
          AND policyname = 'Owners can manage sincerity ratings for own stores'
    ) THEN
        CREATE POLICY "Owners can manage sincerity ratings for own stores"
        ON public.worker_owner_ratings FOR ALL USING (
            owner_id = auth.uid()
            AND EXISTS (
                SELECT 1
                FROM public.stores
                WHERE stores.id = worker_owner_ratings.store_id
                  AND stores.owner_id = auth.uid()
            )
        ) WITH CHECK (
            owner_id = auth.uid()
            AND EXISTS (
                SELECT 1
                FROM public.stores
                WHERE stores.id = worker_owner_ratings.store_id
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
          AND tablename = 'worker_owner_ratings'
          AND policyname = 'Workers can view own sincerity ratings'
    ) THEN
        CREATE POLICY "Workers can view own sincerity ratings"
        ON public.worker_owner_ratings FOR SELECT USING (
            EXISTS (
                SELECT 1
                FROM public.workers
                WHERE workers.id = worker_owner_ratings.worker_id
                  AND workers.user_id = auth.uid()
            )
        );
    END IF;
END
$$;
