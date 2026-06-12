# Runtime Efficiency Benchmark Evidence

**Date:** 2026-06-11
**Scope:** Docker/OrbStack versus Apple `container` repeated runtime measurements before implementation starts.

## Methodology

- Public fixtures only; no private EMSI workloads.
- Images and runtime caches were preserved; this report measures cached-image runtime behavior with fresh benchmark containers and volumes.
- DB scenarios use fresh volumes per iteration.
- Apple backend uses the already discovered PGDATA and DB-IP workarounds; service-name DNS parity is not assumed.
- Percentiles are sample percentiles from the recorded iteration count.
- Runtime stats are one idle snapshot after readiness; process RSS and cgroup memory are collected from inside the container when available.
- No image prune, registry login, Docker build, Apple `container build`, or global cleanup was run.

## Iteration Counts

| Scenario | Runtime | Iterations |
| --- | --- | ---: |
| `simple-web` | `apple-container` | 3 |

## Timing Percentiles

| Scenario | Runtime | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `simple-web` | `apple-container` | `delete` | 3 | 0.114s | 0.118s | 0.118s | 0.118s |
| `simple-web` | `apple-container` | `readiness_probe` | 3 | 0.014s | 0.016s | 0.016s | 0.016s |
| `simple-web` | `apple-container` | `start_command` | 3 | 0.949s | 1.088s | 1.100s | 1.103s |
| `simple-web` | `apple-container` | `stop` | 3 | 0.189s | 0.258s | 0.265s | 0.266s |

## Memory And CPU Percentiles

| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `simple-web` | `apple-container` | `web` | runtime memory | 3 | 14.83MiB | 14.84MiB | 14.84MiB | 14.84MiB |
| `simple-web` | `apple-container` | `web` | process VmRSS | 3 | 5.42MiB | 5.46MiB | 5.47MiB | 5.47MiB |
| `simple-web` | `apple-container` | `web` | cgroup current | 3 | 15.20MiB | 15.39MiB | 15.41MiB | 15.41MiB |
| `simple-web` | `apple-container` | `web` | cgroup peak | 3 | 15.86MiB | 15.88MiB | 15.89MiB | 15.89MiB |
| `simple-web` | `apple-container` | `web` | block read | 3 | 9.13MiB | 9.13MiB | 9.13MiB | 9.13MiB |
| `simple-web` | `apple-container` | `web` | block write | 3 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | net read | 3 | 0.00MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `apple-container` | `web` | net write | 3 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | disk /usr/share/nginx/html | 3 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `apple-container` | `web` | disk /var/cache/nginx | 3 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `simple-web` | `apple-container` | `web` | runtime CPU snapshot | 3 | 0.00% | 0.00% | 0.00% | 0.00% |
| `simple-web` | `apple-container` | `web` | load CPU snapshot | 3 | 7.80% | 8.44% | 8.50% | 8.51% |
| `simple-web` | `apple-container` | `web` | load HTTP requests | 3 | 2905 | 3707 | 3778 | 3796 |

## Apple Runtime Lifecycle

- `container system start`: 0, 0.997s.
- `container system stop`: 0, 0.046s.

## Evidence Files

- Raw JSONL: `docs/evidence/runtime-efficiency/20260611T184208Z-runtime-efficiency-raw.jsonl`
- Summary JSON: `docs/evidence/runtime-efficiency/20260611T184208Z-runtime-efficiency-summary.json`

## Harness Command

```text
scripts/benchmark_runtime_efficiency.py --runtimes apple --simple-iterations 3 --db-iterations 0 --backend-iterations 0
```

## Cleanup Scope

The harness cleaned only resources named with the `cca-bench-*` prefix. Cached images and installed Apple runtime setup were left in place.
