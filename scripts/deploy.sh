#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAMESPACE=${NAMESPACE:-praxis-standalone}
RELEASE=${RELEASE:-praxis-gateway}
CONFIG_DIR=${CONFIG_DIR:-$ROOT/configs/openai-ogx}
CONFIG_FILE=${CONFIG_FILE:-$CONFIG_DIR/config.yaml}
VALUES_FILE=${VALUES_FILE:-$CONFIG_DIR/values.yaml}
API_KEY_SECRET=${API_KEY_SECRET:-openai}
API_KEY_SECRET_KEY=${API_KEY_SECRET_KEY:-OPENAI_API_KEY}
OGX_NAMESPACE=${OGX_NAMESPACE:-redhat-ods-applications}
OGX_SERVICE=${OGX_SERVICE:-ogx-distribution-service}
OGX_PORT=${OGX_PORT:-8321}
OGX_APP_LABEL=${OGX_APP_LABEL:-ogx}
OGX_INSTANCE_LABEL=${OGX_INSTANCE_LABEL:-ogx-distribution}
export OGX_ENDPOINT=${OGX_ENDPOINT:-$OGX_SERVICE.$OGX_NAMESPACE.svc.cluster.local:$OGX_PORT}
export INFERENCE_HOST=${INFERENCE_HOST:-api.openai.com}
export INFERENCE_PORT=${INFERENCE_PORT:-443}

for tool in oc helm python3 envsubst; do
  command -v "$tool" >/dev/null
done
python3 -c 'import yaml'
[[ -r "$CONFIG_FILE" && -r "$CONFIG_DIR/values.yaml" && -r "$VALUES_FILE" ]]
WORK=$(mktemp -d)
trap 'rm -f "$WORK/config.yaml"; rmdir "$WORK"' EXIT
envsubst "\${OGX_ENDPOINT} \${INFERENCE_HOST} \${INFERENCE_PORT}" <"$CONFIG_FILE" >"$WORK/config.yaml"

oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${RELEASE}-ogx
  namespace: ${OGX_NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: "${OGX_APP_LABEL}"
      app.kubernetes.io/instance: "${OGX_INSTANCE_LABEL}"
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: "${NAMESPACE}"
          podSelector:
            matchLabels:
              app.kubernetes.io/name: praxis-gateway
              app.kubernetes.io/instance: "${RELEASE}"
      ports:
        - protocol: TCP
          port: ${OGX_PORT}
YAML

helm upgrade --install "$RELEASE" \
  oci://ghcr.io/praxis-proxy/charts/praxis-gateway --version 0.2.1 \
  --namespace "$NAMESPACE" \
  -f "$ROOT/configs/common-values.yaml" -f "$CONFIG_DIR/values.yaml" -f "$VALUES_FILE" \
  --set-string "fullnameOverride=$RELEASE" \
  --set-string "env[0].valueFrom.secretKeyRef.name=$API_KEY_SECRET" \
  --set-string "env[0].valueFrom.secretKeyRef.key=$API_KEY_SECRET_KEY" \
  --set-file "config.inline=$WORK/config.yaml" \
  --post-renderer "$ROOT/scripts/post-render.py" --wait --timeout 5m
