"""청킹 도입 전에 올라간 매장 문서의 조각(store_document_chunks)을 채운다.

store-rag index는 문서를 저장할 때 조각을 만들지만, 그 전에 올라간 문서에는 조각이 없다.
조각이 없는 문서만 골라 store-rag와 같은 규칙으로 자르고 임베딩해 넣는다.

    python3 scripts/backfill_document_chunks.py ai-service/.env          # 미리보기
    python3 scripts/backfill_document_chunks.py ai-service/.env --apply  # 실제 저장
"""
import json, re, sys, urllib.request

MAX_CHUNK_CHARS = 400
MAX_CHUNKS = 100

env = dict(l.strip().split("=", 1) for l in open(sys.argv[1]) if "=" in l and not l.startswith("#"))
APPLY = "--apply" in sys.argv
URL = env["SUPABASE_URL"].rstrip("/")
SERVICE = env["SUPABASE_SERVICE_KEY"]
OPENAI_KEY = env["OPENAI_API_KEY"]
MODEL = env.get("OPENAI_EMBEDDING_MODEL") or "text-embedding-3-small"


def call(method, url, body=None, headers=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def rest(method, path, body=None):
    return call(method, f"{URL}/rest/v1/{path}", body,
                {"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}", "Prefer": "return=minimal"})


def embed(texts):
    data = call("POST", "https://api.openai.com/v1/embeddings",
                {"model": MODEL, "input": [t[:12000] for t in texts]},
                {"Authorization": f"Bearer {OPENAI_KEY}"})["data"]
    return [d["embedding"] for d in sorted(data, key=lambda d: d["index"])]


# store-rag/index.ts의 splitIntoChunks와 같은 규칙
def split_into_chunks(title, content):
    pieces = []
    for line in (l.strip() for l in re.split(r"\n+", content)):
        if not line:
            continue
        if len(line) <= MAX_CHUNK_CHARS:
            pieces.append(line)
            continue
        current = ""
        for sentence in re.split(r"(?<=[.!?。])\s+", line):
            if current and len(current) + len(sentence) + 1 > MAX_CHUNK_CHARS:
                pieces.append(current)
                current = ""
            current = f"{current} {sentence}" if current else sentence
            while len(current) > MAX_CHUNK_CHARS:
                pieces.append(current[:MAX_CHUNK_CHARS])
                current = current[MAX_CHUNK_CHARS:]
        if current:
            pieces.append(current)
    return [f"{title}: {p}" for p in pieces[:MAX_CHUNKS]]


docs = rest("GET", "store_documents?select=id,store_id,title,content")
chunked = {r["document_id"] for r in rest("GET", "store_document_chunks?select=document_id")}
todo = [d for d in docs if d["id"] not in chunked]
print(f"문서 {len(docs)}개 중 조각이 없는 문서 {len(todo)}개")

for doc in todo:
    chunks = split_into_chunks(doc["title"].strip(), doc["content"].strip())
    print(f"- {doc['title']}: 조각 {len(chunks)}개")
    if not APPLY or not chunks:
        continue
    vectors = embed(chunks)
    rest("POST", "store_document_chunks", [
        {"document_id": doc["id"], "store_id": doc["store_id"], "chunk_index": i,
         "content": c, "embedding": v}
        for i, (c, v) in enumerate(zip(chunks, vectors))
    ])

if not APPLY:
    print("미리보기만 했습니다. 저장하려면 --apply를 붙이세요.")
