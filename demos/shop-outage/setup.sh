#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq filters passed to save()
set -euo pipefail
cd "$(dirname "$0")"

NAMESPACE=${NAMESPACE:-praxis-standalone}
WORKLOAD_NAMESPACE=${WORKLOAD_NAMESPACE:-shop}
RELEASE=${RELEASE:-praxis-gateway}
EMBEDDING_MODEL=${EMBEDDING_MODEL:-vllm-embedding/Nomic-embed-text-v2-moe}
VECTOR_STORE_PROVIDER=${VECTOR_STORE_PROVIDER:-milvus-remote}
URL=http://127.0.0.1:18080
STATE_DIR=../../.cache/demos/shop-outage
STATE=$STATE_DIR/state.json

if [[ -e $STATE ]]; then
  echo "$STATE exists; run demos/shop-outage/cleanup.sh first." >&2
  exit 1
fi
if oc get namespace "$WORKLOAD_NAMESPACE" >/dev/null 2>&1; then
  echo "Namespace $WORKLOAD_NAMESPACE exists; run cleanup.sh or set WORKLOAD_NAMESPACE." >&2
  exit 1
fi
mkdir -p "$STATE_DIR"

api() {
  local path=$1
  shift
  curl -sS --fail-with-body --noproxy '*' --connect-timeout 5 --max-time 60 "$URL$path" "$@"
}

save() {
  jq "$@" "$STATE" >"$STATE.tmp"
  mv "$STATE.tmp" "$STATE"
}

cleanup() {
  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true
}

password() {
  python3 -c 'import secrets; print(secrets.token_urlsafe(18))'
}

jq -n --arg ns "$NAMESPACE" --arg wns "$WORKLOAD_NAMESPACE" \
  '{namespace:$ns,workload_namespace:$wns,files:[],vector_store:null,responses:[]}' >"$STATE"

echo "Deploying shop workloads to $WORKLOAD_NAMESPACE"
oc create namespace "$WORKLOAD_NAMESPACE"
oc label namespace "$WORKLOAD_NAMESPACE" praxis-demo=shop-outage
# The OpenShift MCP server can read the namespace and delete (restart) pods.
oc -n "$WORKLOAD_NAMESPACE" create rolebinding mcp-viewer-view \
  --clusterrole=view --serviceaccount="$NAMESPACE:mcp-viewer"
oc -n "$WORKLOAD_NAMESPACE" create role pod-restarter --verb=get,list,delete --resource=pods
oc -n "$WORKLOAD_NAMESPACE" create rolebinding mcp-viewer-pod-restarter \
  --role=pod-restarter --serviceaccount="$NAMESPACE:mcp-viewer"
oc -n "$WORKLOAD_NAMESPACE" create secret generic shop-app --from-file=app/
oc -n "$WORKLOAD_NAMESPACE" create secret generic orders-db-credentials \
  --from-literal=username=checkout --from-literal=password="$(password)"
oc -n "$WORKLOAD_NAMESPACE" apply -f manifests/orders-db.yaml
oc -n "$WORKLOAD_NAMESPACE" rollout status statefulset/orders-db --timeout=300s
oc -n "$WORKLOAD_NAMESPACE" apply -f manifests/checkout-api.yaml -f manifests/storefront.yaml
oc -n "$WORKLOAD_NAMESPACE" rollout status deployment/checkout-api --timeout=300s
oc -n "$WORKLOAD_NAMESPACE" rollout status deployment/storefront --timeout=300s

# Rotate the database password. orders-db picks it up on restart; checkout-api
# keeps the old value from its environment until its pods are recreated.
echo 'Rotating orders-db credentials'
oc -n "$WORKLOAD_NAMESPACE" set data secret/orders-db-credentials \
  password="$(password)" rotated-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
oc -n "$WORKLOAD_NAMESPACE" rollout restart statefulset/orders-db
oc -n "$WORKLOAD_NAMESPACE" rollout status statefulset/orders-db --timeout=300s

oc -n "$NAMESPACE" port-forward "deployment/$RELEASE" \
  --address 127.0.0.1 18080:8080 19901:9901 >"$STATE_DIR/port-forward.log" 2>&1 &
PF_PID=$!
trap cleanup EXIT
for _ in {1..50}; do
  kill -0 "$PF_PID"
  if curl -fsS --noproxy '*' --max-time 1 http://127.0.0.1:19901/healthy >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
curl -fsS --noproxy '*' --max-time 2 http://127.0.0.1:19901/healthy >/dev/null

echo 'Uploading runbooks and incident reports'
for doc in docs/*.md docs/incidents/*.md; do
  FILE=$(api /v1/files -F "file=@$doc;type=text/markdown" -F purpose=assistants | jq -er '.id')
  save --arg id "$FILE" '.files += [$id]'
  echo "  $(basename "$doc") -> $FILE"
done

echo 'Creating vector store'
STORE=$(api /v1/vector_stores -H 'Content-Type: application/json' -d "$(jq -nc \
  --arg model "$EMBEDDING_MODEL" --arg provider "$VECTOR_STORE_PROVIDER" '
  {name:"praxis-demo-shop-outage",embedding_model:$model,provider_id:$provider}')" | jq -er '.id')
save --arg id "$STORE" '.vector_store = $id'
# OGX uses document_id metadata as the search result's file_id. Chunks stay
# under the default embedding model's 512-token context.
for FILE in $(jq -r '.files[]' "$STATE"); do
  api "/v1/vector_stores/$STORE/files" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg id "$FILE" '{file_id:$id,attributes:{document_id:$id},
      chunking_strategy:{type:"static",static:{max_chunk_size_tokens:300,chunk_overlap_tokens:50}}}')" >/dev/null
done
for FILE in $(jq -r '.files[]' "$STATE"); do
  for _ in {1..60}; do
    STATUS=$(api "/v1/vector_stores/$STORE/files/$FILE" | jq -r '.status')
    case $STATUS in completed|failed|cancelled) break ;; esac
    sleep 2
  done
  if [[ $STATUS != completed ]]; then
    echo "Indexing $FILE: $STATUS" >&2
    exit 1
  fi
done
echo "  $STORE indexed"

echo 'Waiting for checkout-api to become unready'
for _ in {1..30}; do
  READY=$(oc -n "$WORKLOAD_NAMESPACE" get deployment checkout-api -o jsonpath='{.status.readyReplicas}')
  [[ ${READY:-0} -eq 0 ]] && break
  sleep 2
done
if [[ ${READY:-0} -ne 0 ]]; then
  echo 'checkout-api is still ready; check orders-db credentials before running the demo.' >&2
  exit 1
fi
oc -n "$WORKLOAD_NAMESPACE" get pods
echo "Ready. Run: demos/shop-outage/sre-assistant"
