#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACE=${NAMESPACE:-praxis-standalone}
RELEASE=${RELEASE:-praxis-gateway}
MODEL=${MODEL:-gpt-6-luna}
URL=http://127.0.0.1:18080
mkdir -p .cache
WORK=$(mktemp -d "$PWD/.cache/mcp.XXXXXX")
RESOURCES=()

api() {
  local path=$1
  shift
  curl -sS --fail-with-body --noproxy '*' --connect-timeout 5 --max-time 360 "$URL$path" "$@"
}

cleanup() {
  local rc=$? id
  for id in "${RESOURCES[@]}"; do
    if ! api "/v1/responses/$id" -X DELETE | jq -e '.deleted == true' >/dev/null; then
      echo "Cleanup failed: $id" >&2
      rc=1
    fi
  done
  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true
  exit "$rc"
}

echo 'Waiting for the MCP test server'
oc -n "$NAMESPACE" rollout status deployment/mcp-test --timeout=300s

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

echo 'Paid test: two MCP Responses requests, normally four inference calls.'
echo "Artifacts: $WORK"
for stream in false true; do
  echo "MCP discovery and execution, stream=$stream"
  CODE="echo-$RANDOM-$RANDOM"
  REQUEST=$(jq -nc --arg model "$MODEL" --arg code "$CODE" --argjson stream "$stream" '
    {model:$model,reasoning:{effort:"none"},store:true,max_output_tokens:256,stream:$stream,
     input:("Call the echo tool with message " + $code + ". Reply with its result."),
     tools:[{type:"mcp",server_label:"everything",connector_id:"mcp-server",
             allowed_tools:["echo"],require_approval:"never"}]}')
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
  RESOURCES+=("$ID")
  jq -e --arg code "$CODE" '
    .status == "completed" and
    any(.output[]; .type == "mcp_list_tools" and .server_label == "everything" and
      any(.tools[]; .name == "echo")) and
    any(.output[]; .type == "mcp_call" and .name == "echo" and .error == null and
      (.output | contains($code))) and
    any(.output[]?.content[]?; .type == "output_text" and (.text | contains($code)))
  ' "$RESPONSE" >/dev/null
  api "/v1/responses/$ID" | jq -e --slurpfile response "$RESPONSE" '
    .status == "completed" and .output == $response[0].output' >/dev/null
done

echo 'MCP tests passed; deleting test responses and stopping port-forward.'
