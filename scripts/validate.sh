#!/usr/bin/env bash
# Renders every manifest Argo CD would apply and validates it offline:
# the platform chart, each upstream Helm chart with the values from its
# Application, the kustomize apps and the Argo CD bootstrap.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
validate() { # name file
  echo "== $1"
  # Upstream CRD definitions have no published schema; their instances do.
  kubeconform -strict -summary -skip CustomResourceDefinition \
    -schema-location default -schema-location "$CRD_SCHEMAS" "$2"
}

helm template platform platform > "$out/platform.yaml"
validate platform "$out/platform.yaml"

yq -o=json -I=0 'select(.spec.source.chart != null) | .spec' "$out/platform.yaml" |
  while read -r spec; do
    name=$(jq -r .source.chart <<<"$spec")
    jq '.source.helm.valuesObject // {}' <<<"$spec" > "$out/$name.values.json"
    helm template "$name" "$name" \
      --repo "$(jq -r .source.repoURL <<<"$spec")" \
      --version "$(jq -r .source.targetRevision <<<"$spec")" \
      --namespace "$(jq -r .destination.namespace <<<"$spec")" \
      --kube-version 1.37.0 --include-crds \
      --values "$out/$name.values.json" > "$out/$name.yaml"
    validate "$name $(jq -r .source.targetRevision <<<"$spec")" "$out/$name.yaml"
  done

for app in apps/*/; do
  kubectl kustomize "$app" > "$out/app.yaml"
  validate "$app" "$out/app.yaml"
done

kubectl kustomize bootstrap/argocd > "$out/argocd.yaml"
validate bootstrap/argocd "$out/argocd.yaml"
kubeconform -strict -summary -schema-location default -schema-location "$CRD_SCHEMAS" bootstrap/root-app.yaml
