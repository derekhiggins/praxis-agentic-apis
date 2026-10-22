#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NAMESPACE=${NAMESPACE:-praxis-standalone}
WORKLOAD_NAMESPACE=${WORKLOAD_NAMESPACE:-shop}
RELEASE=${RELEASE:-praxis-gateway}
URL=http://127.0.0.1:18080
STATE_DIR=../../.cache/demos/shop-outage
STATE=$STATE_DIR/state.json
RC=0

stop_port_forward() {
  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true
}

if [[ -e $STATE ]]; then
  WORKLOAD_NAMESPACE=$(jq -r '.workload_namespace' "$STATE")
fi
if [[ $(oc get namespace "$WORKLOAD_NAMESPACE" -o jsonpath='{.metadata.labels.praxis-demo}' \
  2>/dev/null) == shop-outage ]]; then
  oc delete namespace "$WORKLOAD_NAMESPACE" --wait=false
fi

if [[ ! -e $STATE ]]; then
  echo "No $STATE; nothing else to delete."
  exit 0
fi

oc -n "$NAMESPACE" port-forward "deployment/$RELEASE" \
  --address 127.0.0.1 18080:8080 19901:9901 >"$STATE_DIR/port-forward.log" 2>&1 &
PF_PID=$!
trap stop_port_forward EXIT
for _ in {1..50}; do
  kill -0 "$PF_PID"
  if curl -fsS --noproxy '*' --max-time 1 http://127.0.0.1:19901/healthy >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
curl -fsS --noproxy '*' --max-time 2 http://127.0.0.1:19901/healthy >/dev/null

PATHS=$(jq -r '
  (.responses[] | "/v1/responses/\(.)"),
  (.vector_store // empty | "/v1/vector_stores/\(.)"),
  (.files[] | "/v1/files/\(.)")' "$STATE")
# 404 covers responses that failed before being stored. Missing vector stores return
# 400 "not found".
BODY=$STATE_DIR/delete-response.json
for path in $PATHS; do
  STATUS=$(curl -sS --noproxy '*' --max-time 30 -o "$BODY" -w '%{http_code}' -X DELETE "$URL$path" || true)
  if [[ $STATUS == 400 ]] && grep -qi 'not found' "$BODY"; then
    STATUS=404
  fi
  case $STATUS in
    200) echo "Deleted $path" ;;
    404) echo "Not found: $path" ;;
    *)
      echo "Cleanup failed ($STATUS): $path" >&2
      RC=1
      ;;
  esac
done

if [[ $RC != 0 ]]; then
  exit 1
fi
rm -f "$STATE" "$BODY"
