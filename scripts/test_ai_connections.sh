#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-Config/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing env file: $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name: empty"
    exit 1
  fi
}

require_var OPENAI_API_KEY
require_var OPENAI_EMBEDDING_MODEL
require_var GEMINI_API_KEY
require_var GEMINI_MODEL

openai_body="$(mktemp)"
gemini_body="$(mktemp)"
trap 'rm -f "$openai_body" "$gemini_body"' EXIT

openai_status="$(
  curl -sS \
    -o "$openai_body" \
    -w "%{http_code}" \
    https://api.openai.com/v1/embeddings \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${OPENAI_EMBEDDING_MODEL}\",\"input\":\"오늘얼마 연결 테스트\"}"
)"

if [[ "$openai_status" == "200" ]] && grep -q '"embedding"' "$openai_body"; then
  echo "OpenAI embeddings: ok"
else
  echo "OpenAI embeddings: failed ($openai_status)"
fi

gemini_status="$(
  curl -sS \
    -o "$gemini_body" \
    -w "%{http_code}" \
    "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"contents":[{"parts":[{"text":"오늘얼마 연결 테스트. OK만 답해."}]}]}'
)"

if [[ "$gemini_status" == "200" ]] && grep -q '"candidates"' "$gemini_body"; then
  echo "Gemini generateContent: ok"
else
  echo "Gemini generateContent: failed ($gemini_status)"
fi
