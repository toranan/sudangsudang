-- Store-specific manuals and notices for the owner knowledge base.
-- Embedding is nullable so the app can manage source documents before the RAG
-- indexing Edge Function is introduced.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.store_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    document_type TEXT NOT NULL DEFAULT 'manual'
        CHECK (document_type IN ('manual', 'notice')),
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    embedding vector(1536),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS store_documents_store_updated_idx
ON public.store_documents (store_id, is_pinned DESC, updated_at DESC);

CREATE INDEX IF NOT EXISTS store_documents_embedding_hnsw_idx
ON public.store_documents USING hnsw (embedding vector_cosine_ops)
WHERE embedding IS NOT NULL;

ALTER TABLE public.store_documents ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_store_documents_updated_at ON public.store_documents;
DROP FUNCTION IF EXISTS public.set_store_documents_updated_at();

CREATE FUNCTION public.set_store_documents_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_store_documents_updated_at
BEFORE UPDATE ON public.store_documents
FOR EACH ROW
EXECUTE FUNCTION public.set_store_documents_updated_at();

DROP POLICY IF EXISTS "Owners can manage documents for own stores" ON public.store_documents;
DROP POLICY IF EXISTS "Workers can view documents for assigned stores" ON public.store_documents;

CREATE POLICY "Owners can manage documents for own stores"
ON public.store_documents FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM public.stores
        WHERE stores.id = store_documents.store_id
          AND stores.owner_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.stores
        WHERE stores.id = store_documents.store_id
          AND stores.owner_id = auth.uid()
    )
);

CREATE POLICY "Workers can view documents for assigned stores"
ON public.store_documents FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM public.workers
        WHERE workers.store_id = store_documents.store_id
          AND workers.user_id = auth.uid()
          AND workers.is_active = TRUE
    )
);

CREATE OR REPLACE FUNCTION public.match_store_documents(
    p_store_id UUID,
    p_query_embedding vector(1536),
    p_match_count INT DEFAULT 5
)
RETURNS TABLE (
    id UUID,
    store_id UUID,
    title TEXT,
    content TEXT,
    document_type TEXT,
    similarity DOUBLE PRECISION
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        store_documents.id,
        store_documents.store_id,
        store_documents.title,
        store_documents.content,
        store_documents.document_type,
        1 - (store_documents.embedding <=> p_query_embedding) AS similarity
    FROM public.store_documents
    WHERE store_documents.store_id = p_store_id
      AND store_documents.embedding IS NOT NULL
    ORDER BY store_documents.embedding <=> p_query_embedding
    LIMIT LEAST(GREATEST(p_match_count, 1), 10);
$$;

REVOKE ALL ON FUNCTION public.match_store_documents(UUID, vector, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_store_documents(UUID, vector, INT) TO authenticated;
