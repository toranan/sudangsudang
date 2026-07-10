#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-Config/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing env file: $ENV_FILE"
  exit 1
fi

unset GEMINI_API_KEY
unset GEMINI_MODEL
unset OPEN_ASSEMBLY_API_KEY
unset OPENAI_API_KEY
unset OPENAI_EMBEDDING_MODEL

set -a
source "$ENV_FILE"
set +a

check_var() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "$value" ]]; then
    echo "$name: empty"
  else
    echo "$name: loaded"
  fi
}

check_var GEMINI_API_KEY
check_var GEMINI_MODEL
check_var OPEN_ASSEMBLY_API_KEY
check_var OPENAI_API_KEY
check_var OPENAI_EMBEDDING_MODEL
