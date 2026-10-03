# Verification evidence

All results below come from real runs. Nothing here is a projection.

## CI on GitHub Actions

| Run | Commit | Result |
|---|---|---|
| [37138930070](https://github.com/michaljakubowski2001/k8s-gitops-portfolio/actions/runs/37138930070) | `357b250` (before the first commit message was renamed; same tree as `5558569`) | First CI run, manual dispatch: validate 14 s, e2e 4 min 1 s; all 8 Applications Synced and Healthy after 122 s; 13/13 checks passed |
| [37139258143](https://github.com/michaljakubowski2001/k8s-gitops-portfolio/actions/runs/37139258143) | [`ba28e65`](https://github.com/michaljakubowski2001/k8s-gitops-portfolio/commit/ba28e657775e27df8c8c8bbdd8c1823450c04e5b) | Push to `main`: validate 17 s, e2e 4 min 5 s; all 8 Applications Synced and Healthy after 121 s; 13/13 checks passed |

Offline validation in the same run (`scripts/validate.sh`, kubeconform `-strict`):

| Rendered from | Resources | Valid | Skipped (CRD definitions) |
|---|---:|---:|---:|
| `platform` chart | 7 | 7 | 0 |
| prometheus-blackbox-exporter 11.19.1 | 7 | 7 | 0 |
| kube-prometheus-stack 91.9.0 | 114 | 104 | 10 |
| sealed-secrets 2.20.0 | 11 | 10 | 1 |
| traefik 41.6.1 | 31 | 6 | 25 |
| `apps/monitoring` | 2 | 2 | 0 |
| `apps/uptime-kuma` | 10 | 10 | 0 |
| `apps/vaultwarden` | 6 | 6 | 0 |
| `bootstrap/argocd` | 60 | 57 | 3 |
| `bootstrap/root-app.yaml` | 1 | 1 | 0 |

## Smoke tests

Output of `scripts/smoke-test.sh` in run 37139258143:

```text
--- Public endpoints through Traefik
PASS  Vaultwarden /alive
PASS  Grafana /api/health
PASS  Grafana dashboard provisioned from Git: K8s GitOps / Platform
PASS  Kuma status page lists 4 monitors
--- Monitoring
PASS  Every scrape target is up (count(up == 0) or vector(0) = 0)
PASS  Every blackbox HTTP probe succeeds (min(probe_success) = 1)
PASS  Argo CD metrics show every app Synced and Healthy (count(argocd_app_info{sync_status!="Synced"} or argocd_app_info{health_status!="Healthy"}) or vector(0) = 0)
PASS  Kuma reports 4/4 monitors up
--- Network policies
PASS  Pod in default namespace cannot reach Vaultwarden
PASS  Pod in default namespace cannot reach Uptime Kuma
PASS  Pod Security (restricted) rejects a privileged pod in vaultwarden
--- Self-healing
PASS  Argo CD recreated a deleted Deployment
PASS  Vaultwarden serves again after self-heal

All checks passed
```

## Local cluster (kind v0.33.0, Kubernetes v1.37.0, Colima 4 CPU / 8 GiB, Apple silicon)

Fresh cluster from `kind delete cluster` to everything healthy, commit `06066a8`:

| Step | Time |
|---|---:|
| `scripts/bootstrap.sh` (cluster, sealing key, Argo CD, root Application) | 73 s |
| `scripts/wait-for-apps.sh` until all 8 Applications Synced and Healthy | 136 s |
| Total | 209 s |

**Kuma configure hook is idempotent.** First sync, then a second sync forced on the same revision:

```text
{"changed":true,"monitors":4}
{"changed":false,"monitors":4}
```

**Pod Security** (`kubectl run --dry-run=server` with `privileged: true` in `vaultwarden`):

```text
Error from server (Forbidden): pods "psa-probe" is forbidden: violates PodSecurity "restricted:latest": privileged (container "psa-probe" must not set securityContext.privileged=true), ...
```

**Memory** (`sum by (namespace) (container_memory_working_set_bytes{container!=""})`, all Applications synced):

| Namespace | Working set |
|---|---:|
| kube-system | 1256 MiB |
| monitoring | 674 MiB |
| argocd | 576 MiB |
| uptime-kuma | 181 MiB |
| traefik | 19 MiB |
| vaultwarden | 12 MiB |
| local-path-storage | 8 MiB |
| **Total** | **2729 MiB** |

## Failures caught during development

The smoke test run on `f97da84`, before the NetworkPolicy fix, is the reason the probe checks exist:

```text
FAIL  Every blackbox HTTP probe succeeds (min(probe_success) = 0, expected 1)
FAIL  Kuma reports 3/4 monitors up
```

Details are in the README's [Troubleshooting log](../README.md#troubleshooting-log).
