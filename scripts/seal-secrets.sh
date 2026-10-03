#!/usr/bin/env bash
# Re-encrypts the application secrets with the public sealing certificate.
# Plain values are read from SECRETS_DIR and never written to the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
SECRETS_DIR=${SECRETS_DIR:-$HOME/.config/k8s-gitops-portfolio}
CERT=bootstrap/sealing-cert.pem

seal() { # namespace name output [key=file ...]
  local namespace=$1 name=$2 output=$3; shift 3
  local args=()
  for pair in "$@"; do args+=(--from-file="$pair"); done
  kubectl create secret generic "$name" --namespace "$namespace" "${args[@]}" \
    --dry-run=client -o yaml |
    kubeseal --cert "$CERT" --format yaml > "$output"
}

printf admin > "$SECRETS_DIR/grafana-admin-user"
seal monitoring grafana-admin apps/monitoring/grafana-admin.sealedsecret.yaml \
  admin-user="$SECRETS_DIR/grafana-admin-user" \
  admin-password="$SECRETS_DIR/grafana-admin-password"
seal uptime-kuma kuma-admin apps/uptime-kuma/kuma-admin.sealedsecret.yaml \
  password="$SECRETS_DIR/kuma-admin-password"
