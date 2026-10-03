#!/usr/bin/env bash
# Creates the kind cluster if needed, restores the Sealed Secrets key,
# installs Argo CD and hands everything else to the root Application.
# Usage: scripts/bootstrap.sh [git-revision]    (default: main)
set -euo pipefail
cd "$(dirname "$0")/.."
REVISION=${1:-main}
SEALING_KEY=${SEALING_KEY:-$HOME/.config/k8s-gitops-portfolio/sealing.key}

if ! kind get clusters | grep -qx gitops; then
  kind create cluster --config kind/cluster.yaml --wait 120s
fi

# Same key pair as bootstrap/sealing-cert.pem, so the SealedSecrets in Git
# decrypt on any rebuilt cluster. The private key never enters the repository.
kubectl create secret tls sealed-secrets-key --namespace kube-system \
  --cert bootstrap/sealing-cert.pem --key "$SEALING_KEY" --dry-run=client -o yaml |
  kubectl label --local -f - sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml |
  kubectl apply -f -

kubectl apply --server-side --force-conflicts -k bootstrap/argocd
for workload in deployment/argocd-repo-server deployment/argocd-server statefulset/argocd-application-controller; do
  kubectl --namespace argocd rollout status "$workload" --timeout=300s
done

REVISION=$REVISION yq '.spec.source.targetRevision = strenv(REVISION) |
  .spec.source.helm.valuesObject.revision = strenv(REVISION)' bootstrap/root-app.yaml |
  kubectl apply -f -
echo "Root Application tracks revision $REVISION"
