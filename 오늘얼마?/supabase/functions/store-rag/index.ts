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
  data?: Array<{ index?: number; embedding?: number[] }>;
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
const ANTHROPIC_MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !OPENAI_API_KEY || !ANTHROPIC_API_KEY) {
  throw new Error("Missing required RAG env vars.");
}

const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

const ANSWER_SYSTEM_PROMPT = [
  "너는 매장 내부 매뉴얼과 공지만 근거로 답하는 알바 업무 도우미다.",
  "질문에 직접 답하는 내용만 쓴다. '참고로' 같은 곁가지 안내, 문서에 없는 제안이나 추측은 쓰지 않는다.",
  "답에 쓰는 사실은 모두 문서를 인용해 근거를 붙인다.",
  "문서에 질문의 답이 없으면 다른 말 없이 [없음]이라고만 쓴다.",
  "질문의 일부만 문서에 있으면 있는 부분만 답하고, 마지막에 '나머지는 사장님께 확인해 보세요.'라고 쓴다.",
  "답변은 한국어로 짧고 구체적으로 쓴다. 순서가 있는 내용이면 번호를 붙인다.",
].join("\n");

const NOT_FOUND_MARK = "[없음]";
// 문서에 답이 없다고 했거나 인용이 하나도 없는 답은 이 문구로 바꾼다.
const NOT_FOUND_ANSWER = "등록된 문서에서 관련 내용을 찾지 못했어요. 사장님께 확인해 보세요.";

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

  // 문서 전체 임베딩(조각이 없을 때의 예비용)과 조각 임베딩을 한 번에 만든다.
  const chunks = splitIntoChunks(title, content);
  const [embedding, ...chunkEmbeddings] = await createEmbeddings([
    `${title}\n\n${content}`,
    ...chunks,
  ]);
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

  // 조각 저장이 실패해도 문서는 이미 저장됐고, 검색은 문서 전체 임베딩으로 돌아간다.
  const documentId = (data as { id: string }).id;
  const { error: deleteError } = await supabase
    .from("store_document_chunks")
    .delete()
    .eq("document_id", documentId);
  if (deleteError) {
    console.error("store-rag: chunk delete failed", deleteError.message);
  } else if (chunks.length > 0) {
    const { error: chunkError } = await supabase
      .from("store_document_chunks")
      .insert(chunks.map((chunk, index) => ({
        document_id: documentId,
        store_id: payload.storeId,
        chunk_index: index,
        content: chunk,
        embedding: chunkEmbeddings[index],
      })));
    if (chunkError) {
      console.error("store-rag: chunk insert failed", chunkError.message);
    }
  }

  return json({ document: data }, 200);
}

const MAX_CHUNK_CHARS = 400;
const MAX_CHUNKS = 100;

// 매뉴얼은 한 줄에 한 단계씩 쓰는 경우가 많아서 줄 단위로 자른다.
// 너무 긴 줄은 문장 단위로 다시 나누고, 조각마다 문서 제목을 붙여 어떤 문서의 내용인지 남긴다.
function splitIntoChunks(title: string, content: string) {
  const pieces: string[] = [];
  for (const line of content.split(/\n+/).map((l) => l.trim()).filter(Boolean)) {
    if (line.length <= MAX_CHUNK_CHARS) {
      pieces.push(line);
      continue;
    }
    let current = "";
    for (const sentence of line.split(/(?<=[.!?。])\s+/)) {
      if (current && current.length + sentence.length + 1 > MAX_CHUNK_CHARS) {
        pieces.push(current);
        current = "";
      }
      current = current ? `${current} ${sentence}` : sentence;
      while (current.length > MAX_CHUNK_CHARS) {
        pieces.push(current.slice(0, MAX_CHUNK_CHARS));
        current = current.slice(MAX_CHUNK_CHARS);
      }
    }
    if (current) pieces.push(current);
  }
  return pieces.slice(0, MAX_CHUNKS).map((piece) => `${title}: ${piece}`);
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
    return json({ answer: NOT_FOUND_ANSWER, sources: [] }, 200);
  }

  const { answer, quotes } = await generateAnswer(question, rows);
  if (quotes.length === 0 || answer.includes(NOT_FOUND_MARK)) {
    return json({ answer: NOT_FOUND_ANSWER, sources: [] }, 200);
  }

  // 인용된 문서만 출처로 보내고, 문서마다 근거 문장을 붙인다.
  const sources = rows
    .map((row, index) => ({
      id: row.id,
      title: row.title,
      documentType: row.document_type,
      similarity: row.similarity,
      quotes: [...new Set(quotes.filter((q) => q.documentIndex === index).map((q) => q.text))],
    }))
    .filter((source) => source.quotes.length > 0);
  return json({ answer, sources }, 200);
}

type Quote = { documentIndex: number; text: string };

// 인용문이 넘긴 문서에 그대로 있는지 다시 확인한 것만 근거로 쓴다.
function verifiedQuotes(content: unknown[], rows: MatchRow[]): Quote[] {
  const quotes: Quote[] = [];
  for (const block of content as Array<{ type: string; citations?: Array<Record<string, unknown>> }>) {
    if (block.type !== "text") continue;
    for (const citation of block.citations ?? []) {
      const index = citation.document_index as number;
      const text = String(citation.cited_text ?? "").trim();
      if (text && rows[index]?.content.includes(text)) {
        quotes.push({ documentIndex: index, text });
      }
    }
  }
  return quotes;
}

async function createEmbedding(input: string) {
  const [embedding] = await createEmbeddings([input]);
  return embedding;
}

async function createEmbeddings(inputs: string[]) {
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: OPENAI_EMBEDDING_MODEL,
      input: inputs.map((input) => input.slice(0, 12000)),
    }),
  });

  const body = (await response.json()) as EmbeddingResponse;
  if (!response.ok) {
    throw new Error(body.error?.message ?? "Embedding request failed");
  }

  const embeddings = [...(body.data ?? [])]
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
    .map((item) => item.embedding);
  if (embeddings.length !== inputs.length || embeddings.some((e) => !e)) {
    throw new Error("Embedding response missing vector");
  }
  return embeddings as number[][];
}

async function generateAnswer(question: string, matches: MatchRow[]) {
  // 문서마다 인용을 켜서 넘기면, 답변의 각 부분이 어느 문장을 근거로 했는지 함께 돌아온다.
  const documents = matches.map((row) => ({
    type: "document",
    source: { type: "text", media_type: "text/plain", data: row.content },
    title: row.title,
    context: row.document_type === "notice" ? "매장 공지" : "매장 매뉴얼",
    citations: { enabled: true },
  }));

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
      content: [...documents, { type: "text", text: `질문: ${question}` }],
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
  return { answer: text, quotes: verifiedQuotes(response.content, matches) };
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
