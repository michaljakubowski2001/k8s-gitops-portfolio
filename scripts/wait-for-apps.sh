#!/usr/bin/env bash
# Waits until every Argo CD Application is Synced and Healthy.
set -euo pipefail
TIMEOUT=${TIMEOUT:-900}
EXPECTED=${EXPECTED:-8}
deadline=$((SECONDS + TIMEOUT))
status() {
  kubectl --namespace argocd get applications.argoproj.io \
    -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision' 2>/dev/null
}
while (( SECONDS < deadline )); do
  table=$(status || true)
  total=$(tail -n +2 <<<"$table" | grep -c . || true)
  ready=$(tail -n +2 <<<"$table" | awk '$2 == "Synced" && $3 == "Healthy"' | grep -c . || true)
  if (( total == EXPECTED && ready == EXPECTED )); then
    echo "$table"
    echo "All $EXPECTED Applications are Synced and Healthy after ${SECONDS}s"
    exit 0
  fi
  echo "[${SECONDS}s] $ready/$EXPECTED ready"
  sleep 15
done
echo "Timed out after ${TIMEOUT}s" >&2
status >&2 || true
kubectl --namespace argocd get applications.argoproj.io -o yaml |
  yq '.items[] | select(.status.health.status != "Healthy" or .status.sync.status != "Synced") |
      {"app": .metadata.name, "conditions": .status.conditions, "operation": .status.operationState.message}' >&2 || true
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -30 >&2 || true
exit 1
