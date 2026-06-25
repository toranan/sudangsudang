-- Allow owner sincerity ratings in 0.5 steps (1.0 ~ 5.0).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'worker_owner_ratings'
          AND column_name = 'rating'
    ) THEN
        ALTER TABLE public.worker_owner_ratings
            ALTER COLUMN rating TYPE NUMERIC(2,1)
            USING rating::numeric;

        ALTER TABLE public.worker_owner_ratings
            DROP CONSTRAINT IF EXISTS worker_owner_ratings_rating_check;

        ALTER TABLE public.worker_owner_ratings
            ADD CONSTRAINT worker_owner_ratings_rating_check
            CHECK (
                rating >= 1.0
                AND rating <= 5.0
                AND (rating * 2) = round(rating * 2)
            );
    END IF;
END
$$;
