#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACE=${NAMESPACE:-praxis-standalone}
RELEASE=${RELEASE:-praxis-gateway}
URL=http://127.0.0.1:18080
mkdir -p .cache
WORK=$(mktemp -d "$PWD/.cache/smoke.XXXXXX")
CONVERSATION=

api() {
  curl -sS --fail-with-body --noproxy '*' --connect-timeout 5 --max-time 10 "$URL$1" "${@:2}"
}

cleanup() {
  local rc=$?
  if [[ -n "$CONVERSATION" ]]; then
    if ! api "/v1/conversations/$CONVERSATION" -X DELETE | jq -e '.deleted == true' >/dev/null; then
      echo "Cleanup failed: /v1/conversations/$CONVERSATION" >&2
      rc=1
    fi
  fi
  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true
  exit "$rc"
}

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

echo "Smoke test: no inference calls. Artifacts: $WORK"
CONVERSATION=$(api /v1/conversations -H 'Content-Type: application/json' \
  -d '{"metadata":{"test":"smoke"}}' | jq -er '.id')
api "/v1/conversations/$CONVERSATION" -H 'Content-Type: application/json' \
  -d '{"metadata":{"test":"updated"}}' >/dev/null
api "/v1/conversations/$CONVERSATION" | jq -e '.metadata.test == "updated"' >/dev/null
echo 'Smoke test passed; deleting test conversation and stopping port-forward.'
