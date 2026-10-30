-- 매장 문서를 줄·문단 단위 조각으로 나눠 임베딩한다.
-- 문서 하나를 통째로 임베딩하면 여러 주제가 섞여 질문과의 유사도가 묽어진다.
-- (문서 5개, 질문 30개 실험에서 정답 문서 1등 비율 10/15 → 12/15)
-- 조각은 store-rag index가 문서를 저장할 때 다시 만든다.

CREATE TABLE IF NOT EXISTS public.store_document_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES public.store_documents(id) ON DELETE CASCADE,
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    chunk_index INT NOT NULL,
    content TEXT NOT NULL,
    embedding vector(1536) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (document_id, chunk_index)
);

CREATE INDEX IF NOT EXISTS store_document_chunks_store_idx
ON public.store_document_chunks (store_id);

CREATE INDEX IF NOT EXISTS store_document_chunks_embedding_hnsw_idx
ON public.store_document_chunks USING hnsw (embedding vector_cosine_ops);

ALTER TABLE public.store_document_chunks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners can manage chunks for own stores" ON public.store_document_chunks;
DROP POLICY IF EXISTS "Workers can view chunks for assigned stores" ON public.store_document_chunks;

-- 조각의 store_id가 문서의 store_id와 같을 때만 넣을 수 있게 한다.
CREATE POLICY "Owners can manage chunks for own stores"
ON public.store_document_chunks FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM public.stores
        WHERE stores.id = store_document_chunks.store_id
          AND stores.owner_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.store_documents
        JOIN public.stores ON stores.id = store_documents.store_id
        WHERE store_documents.id = store_document_chunks.document_id
          AND store_documents.store_id = store_document_chunks.store_id
          AND stores.owner_id = auth.uid()
    )
);

CREATE POLICY "Workers can view chunks for assigned stores"
ON public.store_document_chunks FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM public.workers
        WHERE workers.store_id = store_document_chunks.store_id
          AND workers.user_id = auth.uid()
          AND workers.is_active = TRUE
    )
);

-- 반환 형태는 그대로 두고, 검색만 조각 단위로 바꾼다.
-- 문서마다 가장 비슷한 조각의 점수를 그 문서의 유사도로 쓰고, 답변 근거로는 문서 전체를 돌려준다.
-- 아직 조각이 없는 문서는 기존 문서 임베딩으로 찾는다.
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
    WITH chunk_hits AS (
        SELECT
            store_document_chunks.document_id,
            1 - (store_document_chunks.embedding <=> p_query_embedding) AS similarity
        FROM public.store_document_chunks
        WHERE store_document_chunks.store_id = p_store_id
        ORDER BY store_document_chunks.embedding <=> p_query_embedding
        LIMIT 50
    ),
    unchunked_hits AS (
        SELECT
            store_documents.id AS document_id,
            1 - (store_documents.embedding <=> p_query_embedding) AS similarity
        FROM public.store_documents
        WHERE store_documents.store_id = p_store_id
          AND store_documents.embedding IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM public.store_document_chunks
              WHERE store_document_chunks.document_id = store_documents.id
          )
    ),
    best AS (
        SELECT hits.document_id, MAX(hits.similarity) AS similarity
        FROM (
            SELECT * FROM chunk_hits
            UNION ALL
            SELECT * FROM unchunked_hits
        ) AS hits
        GROUP BY hits.document_id
    )
    SELECT
        store_documents.id,
        store_documents.store_id,
        store_documents.title,
        store_documents.content,
        store_documents.document_type,
        best.similarity
    FROM best
    JOIN public.store_documents ON store_documents.id = best.document_id
    WHERE store_documents.store_id = p_store_id
    ORDER BY best.similarity DESC
    LIMIT LEAST(GREATEST(p_match_count, 1), 10);
$$;

REVOKE ALL ON FUNCTION public.match_store_documents(UUID, vector, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_store_documents(UUID, vector, INT) TO authenticated;
