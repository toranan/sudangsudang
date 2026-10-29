import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk";

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
// 임베딩은 OpenAI, 답변 생성은 Claude.
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-opus-5-5";

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !OPENAI_API_KEY || !ANTHROPIC_API_KEY) {
  throw new Error("Missing required RAG env vars.");
}

const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

const ANSWER_SYSTEM_PROMPT = [
  "너는 매장 내부 매뉴얼과 공지만 근거로 답하는 알바 업무 도우미다.",
  "주어진 문서에 없는 내용은 추측하지 말고, 문서에서 찾지 못했다고 말한 뒤 사장님께 확인해 보라고 안내한다.",
  "답변은 한국어로 짧고 구체적으로 쓴다. 순서가 있는 내용이면 번호를 붙인다.",
  "마지막 줄에 참고한 문서 제목을 '참고: 제목' 형식으로 붙인다.",
].join("\n");

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

  const response = await anthropic.beta.messages.create({
    model: ANTHROPIC_MODEL,
    max_tokens: 2048,
    // 짧은 문서 Q&A라 깊은 추론이 필요 없다.
    output_config: { effort: "low" },
    // 안전 분류기가 거절하면 서버가 다른 모델로 자동 재시도한다.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: ANSWER_SYSTEM_PROMPT,
    messages: [{
      role: "user",
      content: `<documents>\n${context}\n</documents>\n\n질문: ${question}`,
    }],
  } as Parameters<typeof anthropic.beta.messages.create>[0]);

  if (response.stop_reason === "refusal") {
    throw new Error("Claude declined to answer");
  }
  const text = response.content
    .map((block) => (block.type === "text" ? block.text : ""))
    .join("")
    .trim();

  if (!text) {
    throw new Error("Claude response missing answer");
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
