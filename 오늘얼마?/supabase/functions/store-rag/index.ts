import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type StoreRagRequest =
  | {
      action: "index";
      id?: string;
      storeId: string;
      title: string;
      content: string;
      documentType: "manual" | "notice";
      isPinned?: boolean;
    }
  | {
      action: "ask";
      storeId: string;
      question: string;
    };

type EmbeddingResponse = {
  data?: Array<{ embedding?: number[] }>;
  error?: { message?: string };
};

type GeminiResponse = {
  candidates?: Array<{
    content?: {
      parts?: Array<{ text?: string }>;
    };
  }>;
  error?: { message?: string };
};

type MatchRow = {
  id: string;
  title: string;
  content: string;
  document_type: "manual" | "notice";
  similarity: number;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const OPENAI_EMBEDDING_MODEL =
  Deno.env.get("OPENAI_EMBEDDING_MODEL") ?? "text-embedding-3-small";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !OPENAI_API_KEY || !GEMINI_API_KEY) {
  throw new Error("Missing required RAG env vars.");
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method Not Allowed" }, 405);
  }

  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }

  let payload: StoreRagRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  try {
    if (payload.action === "index") {
      return await indexDocument(supabase, payload);
    }
    return await answerQuestion(supabase, payload);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: message }, 500);
  }
});

async function indexDocument(
  supabase: ReturnType<typeof createClient>,
  payload: Extract<StoreRagRequest, { action: "index" }>,
) {
  const title = payload.title.trim();
  const content = payload.content.trim();

  if (!payload.storeId || !title || !content) {
    return json({ error: "Missing document fields" }, 400);
  }

  const embedding = await createEmbedding(`${title}\n\n${content}`);
  const rowPayload = {
    store_id: payload.storeId,
    title,
    content,
    document_type: payload.documentType,
    is_pinned: payload.isPinned ?? false,
    embedding,
    metadata: {
      indexed_at: new Date().toISOString(),
      embedding_model: OPENAI_EMBEDDING_MODEL,
    },
  };

  const query = payload.id
    ? supabase
        .from("store_documents")
        .update(rowPayload)
        .eq("id", payload.id)
        .eq("store_id", payload.storeId)
        .select()
        .single()
    : supabase
        .from("store_documents")
        .insert(rowPayload)
        .select()
        .single();

  const { data, error } = await query;
  if (error) {
    return json({ error: error.message }, 400);
  }

  return json({ document: data }, 200);
}

async function answerQuestion(
  supabase: ReturnType<typeof createClient>,
  payload: Extract<StoreRagRequest, { action: "ask" }>,
) {
  const question = payload.question.trim();
  if (!payload.storeId || !question) {
    return json({ error: "Missing question" }, 400);
  }

  const embedding = await createEmbedding(question);
  const { data: matches, error } = await supabase.rpc("match_store_documents", {
    p_store_id: payload.storeId,
    p_query_embedding: embedding,
    p_match_count: 5,
  });

  if (error) {
    return json({ error: error.message }, 400);
  }

  const rows = ((matches ?? []) as MatchRow[]).filter((row) => row.similarity >= 0.2);
  if (rows.length === 0) {
    return json({
      answer: "등록된 문서에서 관련 내용을 찾지 못했어요.",
      sources: [],
    }, 200);
  }

  const answer = await generateAnswer(question, rows);
  return json({
    answer,
    sources: rows.map((row) => ({
      id: row.id,
      title: row.title,
      documentType: row.document_type,
      similarity: row.similarity,
    })),
  }, 200);
}

async function createEmbedding(input: string) {
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: OPENAI_EMBEDDING_MODEL,
      input: input.slice(0, 12000),
    }),
  });

  const body = (await response.json()) as EmbeddingResponse;
  if (!response.ok) {
    throw new Error(body.error?.message ?? "Embedding request failed");
  }

  const embedding = body.data?.[0]?.embedding;
  if (!embedding) {
    throw new Error("Embedding response missing vector");
  }
  return embedding;
}

async function generateAnswer(question: string, matches: MatchRow[]) {
  const context = matches
    .map((row, index) =>
      `[${index + 1}] ${row.title} (${row.document_type})\n${row.content.slice(0, 1800)}`
    )
    .join("\n\n");

  const prompt = [
    "너는 매장 내부 매뉴얼과 공지만 근거로 답하는 알바 업무 도우미다.",
    "아래 문서에 없는 내용은 추측하지 말고 모른다고 답한다.",
    "답변은 한국어로 짧고 구체적으로 작성한다.",
    "마지막 줄에 참고 문서 제목을 붙인다.",
    "",
    `질문: ${question}`,
    "",
    `문서:\n${context}`,
  ].join("\n");

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 512,
        },
      }),
    },
  );

  const body = (await response.json()) as GeminiResponse;
  if (!response.ok) {
    throw new Error(body.error?.message ?? "Gemini request failed");
  }

  const text = body.candidates?.[0]?.content?.parts
    ?.map((part) => part.text ?? "")
    .join("")
    .trim();

  if (!text) {
    throw new Error("Gemini response missing answer");
  }
  return text;
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
