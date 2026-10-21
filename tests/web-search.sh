#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACE=${NAMESPACE:-praxis-standalone}
RELEASE=${RELEASE:-praxis-gateway}
MODEL=${MODEL:-gpt-6-luna}
URL=http://127.0.0.1:18080
mkdir -p .cache
WORK=$(mktemp -d "$PWD/.cache/web-search.XXXXXX")
RESOURCES=()

api() {
  local path=$1
  shift
  curl -sS --fail-with-body --noproxy '*' --connect-timeout 5 --max-time 360 "$URL$path" "$@"
}

cleanup() {
  local rc=$? i
  for ((i=${#RESOURCES[@]}-1; i>=0; i--)); do
    if ! api "${RESOURCES[i]}" -X DELETE | jq -e '.deleted == true' >/dev/null; then
      echo "Cleanup failed: ${RESOURCES[i]}" >&2
      rc=1
    fi
  done
  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true
  exit "$rc"
}

if [[ -z $(oc -n "$NAMESPACE" get "deployment/$RELEASE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="praxis")].env[?(@.name=="WEB_SEARCH_API_KEY")].name}') ]]; then
  echo "Web search is not enabled on $RELEASE; deploy with ENABLE_WEB_SEARCH=true" >&2
  exit 1
fi

oc -n "$NAMESPACE" port-forward "deployment/$RELEASE" \
  --address 127.0.0.1 18080:8080 19901:9901 >"$WORK/port-forward.log" 2>&1 &
PF_PID=$!
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for _ in {1..50}; do
  kill -0 "$PF_PID"
  if curl -fsS --noproxy '*' --max-time 1 http://127.0.0.1:19901/healthy >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
curl -fsS --noproxy '*' --max-time 2 http://127.0.0.1:19901/healthy >/dev/null

echo 'Paid test: two web-search Responses requests, normally four inference calls, plus Brave searches.'
echo "Artifacts: $WORK"
for stream in false true; do
  echo "Hosted web_search loop, stream=$stream"
  REQUEST=$(jq -nc --arg model "$MODEL" --argjson stream "$stream" '
    {model:$model,reasoning:{effort:"none"},store:true,max_output_tokens:256,stream:$stream,
     input:"Search the web for the OpenShift AI documentation. Briefly summarize what you found and include a source URL.",
     tools:[{type:"web_search",search_context_size:"low"}],
     tool_choice:{type:"web_search"},include:["web_search_call.action.sources"]}')
  api /v1/responses -H 'Content-Type: application/json' -d "$REQUEST" >"$WORK/response-$stream.raw"
  if [[ $stream == true ]]; then
    sed -n 's/^data: //p' "$WORK/response-$stream.raw" | sed '/^\[DONE\]\r\?$/d' | jq -se '
      if any(.[]; .type == "error" or .type == "response.failed" or .type == "response.incomplete")
      then error("stream failed") else
        [.[] | select(.type == "response.completed")] |
        if length == 1 then .[0].response else error("missing completed response") end
      end' >"$WORK/response-$stream.json"
  else
    cp "$WORK/response-$stream.raw" "$WORK/response-$stream.json"
  fi
  RESPONSE="$WORK/response-$stream.json"
  ID=$(jq -er '.id' "$RESPONSE")
  RESOURCES+=("/v1/responses/$ID")
  jq -e '
    .status == "completed" and
    any(.output[]; .type == "web_search_call" and .status == "completed" and
      .action.type == "search" and (.action.query | length > 0) and
      any(.action.sources[]?; .url | test("^https?://"))) and
    any(.output[]?.content[]?; .type == "output_text" and (.text | length > 0))
  ' "$RESPONSE" >/dev/null
  api "/v1/responses/$ID" | jq -e --slurpfile response "$RESPONSE" '
    .status == "completed" and .output == $response[0].output' >/dev/null
  api "/v1/responses/$ID/input_items" | jq -e '.data | length > 0' >/dev/null
done

echo 'Web-search tests passed; deleting test responses and stopping port-forward.'
