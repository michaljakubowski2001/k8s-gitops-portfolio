#!/usr/bin/env bash
# End-to-end checks of a synced cluster: public endpoints through Traefik,
# monitoring data, network isolation and Argo CD self-healing.
set -euo pipefail
PORT=${INGRESS_PORT:-8080}
CURL_IMAGE=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
failures=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# GET through Traefik with the right Host; retries while services settle.
get() { # host path
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 10 --resolve "$1:$PORT:127.0.0.1" "http://$1:$PORT$2"; then return 0; fi
    sleep 5
  done
  return 1
}
# Instant PromQL query through the API server's service proxy.
prom() {
  local query
  query=$(jq -rn --arg q "$1" '$q | @uri')
  kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:http-web/proxy/api/v1/query?query=$query" |
    jq -r '.data.result[0].value[1] // "none"'
}
# Retries a PromQL query until it returns the expected value.
expect_prom() { # description query expected
  local value=none
  for _ in $(seq 1 24); do
    value=$(prom "$2")
    [[ $value == "$3" ]] && { pass "$1 ($2 = $value)"; return; }
    sleep 10
  done
  fail "$1 ($2 = $value, expected $3)"
}

echo '--- Public endpoints through Traefik'
get vault.localhost /alive >/dev/null && pass 'Vaultwarden /alive' || fail 'Vaultwarden /alive'
get grafana.localhost /api/health >/dev/null && pass 'Grafana /api/health' || fail 'Grafana /api/health'
dashboard=$(get grafana.localhost /api/dashboards/uid/k8s-gitops-platform | jq -r '.dashboard.title' || true)
[[ $dashboard == 'K8s GitOps / Platform' ]] && pass "Grafana dashboard provisioned from Git: $dashboard" || fail 'Grafana dashboard'
monitors=$(get status.localhost /api/status-page/portfolio | jq '[.publicGroupList[].monitorList[]] | length' || true)
[[ $monitors == 4 ]] && pass "Kuma status page lists $monitors monitors" || fail "Kuma status page lists ${monitors:-0} monitors"

echo '--- Monitoring'
expect_prom 'Every scrape target is up' 'count(up == 0) or vector(0)' 0
expect_prom 'Every blackbox HTTP probe succeeds' 'min(probe_success)' 1
expect_prom 'Argo CD metrics show every app Synced and Healthy' \
  'count(argocd_app_info{sync_status!="Synced"} or argocd_app_info{health_status!="Healthy"}) or vector(0)' 0
up=0
for _ in $(seq 1 18); do
  up=$(get status.localhost /api/status-page/heartbeat/portfolio |
    jq '[.heartbeatList[] | last | select(.status == 1)] | length' || echo 0)
  [[ $up == 4 ]] && break
  sleep 10
done
[[ $up == 4 ]] && pass 'Kuma reports 4/4 monitors up' || fail "Kuma reports $up/4 monitors up"

echo '--- Network policies'
probe_from() { # namespace url -> exit code of curl inside a throwaway pod
  kubectl run "np-probe-$RANDOM" --namespace "$1" --rm -i --restart=Never --quiet \
    --image "$CURL_IMAGE" --overrides '{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"'"$CURL_IMAGE"'","args":["-fsS","-o","/dev/null","--max-time","5","'"$2"'"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
    >/dev/null 2>&1 && echo 0 || echo 1
}
[[ $(probe_from default http://vaultwarden.vaultwarden.svc:8080/alive) == 1 ]] \
  && pass 'Pod in default namespace cannot reach Vaultwarden' || fail 'Default namespace reached Vaultwarden'
[[ $(probe_from default http://uptime-kuma.uptime-kuma.svc:3001/) == 1 ]] \
  && pass 'Pod in default namespace cannot reach Uptime Kuma' || fail 'Default namespace reached Uptime Kuma'

echo '--- Self-healing'
kubectl --namespace vaultwarden delete deployment vaultwarden --wait=true >/dev/null
healed=false
for _ in $(seq 1 36); do
  if kubectl --namespace vaultwarden rollout status deployment/vaultwarden --timeout=5s >/dev/null 2>&1; then healed=true; break; fi
  sleep 5
done
$healed && pass 'Argo CD recreated a deleted Deployment' || fail 'Deleted Deployment was not recreated'
get vault.localhost /alive >/dev/null && pass 'Vaultwarden serves again after self-heal' || fail 'Vaultwarden after self-heal'

echo
if (( failures )); then echo "$failures check(s) failed"; exit 1; fi
echo 'All checks passed'
