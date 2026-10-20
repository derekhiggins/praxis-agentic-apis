#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-praxis-standalone}
RELEASE=${RELEASE:-praxis-gateway}
OGX_NAMESPACE=${OGX_NAMESPACE:-redhat-ods-applications}

for tool in helm oc; do
  command -v "$tool" >/dev/null
done

helm uninstall "$RELEASE" --namespace "$NAMESPACE" \
  --ignore-not-found --wait --timeout 5m
oc -n "$OGX_NAMESPACE" delete networkpolicy "${RELEASE}-ogx" --ignore-not-found
