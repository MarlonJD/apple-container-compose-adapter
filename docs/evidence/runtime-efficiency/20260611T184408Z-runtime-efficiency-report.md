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
| `backend-shaped` | `apple-container` | 2 |
| `postgres-db-only` | `apple-container` | 5 |
| `simple-web` | `apple-container` | 5 |

## Timing Percentiles

| Scenario | Runtime | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `api_start_command` | 2 | 1.001s | 1.099s | 1.108s | 1.110s |
| `backend-shaped` | `apple-container` | `db_health_wait` | 2 | 1.156s | 1.161s | 1.161s | 1.162s |
| `backend-shaped` | `apple-container` | `db_start_command` | 2 | 0.854s | 0.865s | 0.865s | 0.866s |
| `backend-shaped` | `apple-container` | `delete` | 2 | 0.211s | 0.235s | 0.238s | 0.238s |
| `backend-shaped` | `apple-container` | `migrate` | 2 | 1.202s | 1.208s | 1.208s | 1.208s |
| `backend-shaped` | `apple-container` | `network_create` | 2 | 0.105s | 0.107s | 0.108s | 0.108s |
| `backend-shaped` | `apple-container` | `network_delete` | 2 | 0.071s | 0.105s | 0.108s | 0.108s |
| `backend-shaped` | `apple-container` | `readiness_probe` | 2 | 1.022s | 1.023s | 1.023s | 1.023s |
| `backend-shaped` | `apple-container` | `seed` | 2 | 1.125s | 1.246s | 1.257s | 1.259s |
| `backend-shaped` | `apple-container` | `stop` | 2 | 5.327s | 5.457s | 5.469s | 5.472s |
| `backend-shaped` | `apple-container` | `volume_create` | 2 | 0.531s | 0.575s | 0.579s | 0.580s |
| `backend-shaped` | `apple-container` | `volume_delete` | 2 | 0.086s | 0.104s | 0.106s | 0.106s |
| `postgres-db-only` | `apple-container` | `delete` | 5 | 0.124s | 0.130s | 0.130s | 0.131s |
| `postgres-db-only` | `apple-container` | `health_wait` | 5 | 1.174s | 2.097s | 2.258s | 2.298s |
| `postgres-db-only` | `apple-container` | `start_command` | 5 | 0.871s | 0.919s | 0.925s | 0.926s |
| `postgres-db-only` | `apple-container` | `stop` | 5 | 0.193s | 2.747s | 3.246s | 3.371s |
| `postgres-db-only` | `apple-container` | `volume_create` | 5 | 0.560s | 0.978s | 0.985s | 0.987s |
| `postgres-db-only` | `apple-container` | `volume_delete` | 5 | 0.076s | 0.083s | 0.083s | 0.083s |
| `simple-web` | `apple-container` | `delete` | 5 | 0.136s | 0.143s | 0.143s | 0.143s |
| `simple-web` | `apple-container` | `readiness_probe` | 5 | 0.014s | 0.016s | 0.016s | 0.016s |
| `simple-web` | `apple-container` | `start_command` | 5 | 0.821s | 1.004s | 1.035s | 1.043s |
| `simple-web` | `apple-container` | `stop` | 5 | 0.299s | 4.480s | 5.293s | 5.496s |

## Memory And CPU Percentiles

| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `db` | runtime memory | 2 | 188.32MiB | 188.34MiB | 188.34MiB | 188.34MiB |
| `backend-shaped` | `apple-container` | `db` | process VmRSS | 2 | 26.68MiB | 26.71MiB | 26.71MiB | 26.71MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup current | 2 | 188.43MiB | 188.56MiB | 188.57MiB | 188.57MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup peak | 2 | 200.07MiB | 200.17MiB | 200.18MiB | 200.18MiB |
| `backend-shaped` | `apple-container` | `db` | block read | 2 | 81.05MiB | 81.05MiB | 81.05MiB | 81.05MiB |
| `backend-shaped` | `apple-container` | `db` | block write | 2 | 50.61MiB | 50.62MiB | 50.62MiB | 50.62MiB |
| `backend-shaped` | `apple-container` | `db` | net read | 2 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `backend-shaped` | `apple-container` | `db` | net write | 2 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `db` | disk /var/lib/postgresql/data | 2 | 45.79MiB | 45.79MiB | 45.79MiB | 45.79MiB |
| `backend-shaped` | `apple-container` | `db` | runtime CPU snapshot | 2 | 0.07% | 0.08% | 0.08% | 0.08% |
| `backend-shaped` | `apple-container` | `db` | load CPU snapshot | 2 | 65.19% | 91.19% | 93.50% | 94.08% |
| `backend-shaped` | `apple-container` | `api` | runtime memory | 2 | 31.59MiB | 31.62MiB | 31.62MiB | 31.62MiB |
| `backend-shaped` | `apple-container` | `api` | process VmRSS | 2 | 18.61MiB | 18.63MiB | 18.63MiB | 18.63MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup current | 2 | 33.57MiB | 34.07MiB | 34.11MiB | 34.12MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup peak | 2 | 33.82MiB | 34.32MiB | 34.36MiB | 34.37MiB |
| `backend-shaped` | `apple-container` | `api` | block read | 2 | 18.12MiB | 18.12MiB | 18.12MiB | 18.12MiB |
| `backend-shaped` | `apple-container` | `api` | block write | 2 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `api` | net read | 2 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `backend-shaped` | `apple-container` | `api` | net write | 2 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `api` | runtime CPU snapshot | 2 | 0.03% | 0.03% | 0.03% | 0.03% |
| `backend-shaped` | `apple-container` | `api` | load CPU snapshot | 2 | 33.57% | 34.67% | 34.77% | 34.79% |
| `backend-shaped` | `apple-container` | `api` | load HTTP requests | 2 | 2092 | 2263 | 2278 | 2282 |
| `postgres-db-only` | `apple-container` | `db` | runtime memory | 5 | 186.90MiB | 187.33MiB | 187.35MiB | 187.36MiB |
| `postgres-db-only` | `apple-container` | `db` | process VmRSS | 5 | 26.60MiB | 26.74MiB | 26.75MiB | 26.76MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup current | 5 | 187.64MiB | 187.74MiB | 187.76MiB | 187.76MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup peak | 5 | 200.43MiB | 201.47MiB | 201.68MiB | 201.73MiB |
| `postgres-db-only` | `apple-container` | `db` | block read | 5 | 81.05MiB | 81.05MiB | 81.05MiB | 81.05MiB |
| `postgres-db-only` | `apple-container` | `db` | block write | 5 | 50.41MiB | 50.41MiB | 50.41MiB | 50.41MiB |
| `postgres-db-only` | `apple-container` | `db` | net read | 5 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `postgres-db-only` | `apple-container` | `db` | net write | 5 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `postgres-db-only` | `apple-container` | `db` | disk /var/lib/postgresql/data | 5 | 45.70MiB | 45.70MiB | 45.70MiB | 45.70MiB |
| `postgres-db-only` | `apple-container` | `db` | runtime CPU snapshot | 5 | 0.06% | 0.09% | 0.10% | 0.10% |
| `postgres-db-only` | `apple-container` | `db` | load CPU snapshot | 5 | 56.33% | 74.82% | 76.09% | 76.41% |
| `simple-web` | `apple-container` | `web` | runtime memory | 5 | 14.61MiB | 14.85MiB | 14.85MiB | 14.85MiB |
| `simple-web` | `apple-container` | `web` | process VmRSS | 5 | 5.47MiB | 5.48MiB | 5.48MiB | 5.48MiB |
| `simple-web` | `apple-container` | `web` | cgroup current | 5 | 15.09MiB | 15.91MiB | 16.06MiB | 16.10MiB |
| `simple-web` | `apple-container` | `web` | cgroup peak | 5 | 15.88MiB | 16.39MiB | 16.44MiB | 16.46MiB |
| `simple-web` | `apple-container` | `web` | block read | 5 | 9.13MiB | 9.13MiB | 9.13MiB | 9.13MiB |
| `simple-web` | `apple-container` | `web` | block write | 5 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | net read | 5 | 0.00MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `apple-container` | `web` | net write | 5 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | disk /usr/share/nginx/html | 5 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `apple-container` | `web` | disk /var/cache/nginx | 5 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `simple-web` | `apple-container` | `web` | runtime CPU snapshot | 5 | 0.00% | 0.00% | 0.00% | 0.00% |
| `simple-web` | `apple-container` | `web` | load CPU snapshot | 5 | 0.62% | 5.83% | 6.58% | 6.77% |
| `simple-web` | `apple-container` | `web` | load HTTP requests | 5 | 1996 | 3818 | 4088 | 4156 |

## Apple Runtime Lifecycle

- `container system start`: 0, 0.355s.
- `container system stop`: 0, 0.054s.

## Evidence Files

- Raw JSONL: `docs/evidence/runtime-efficiency/20260611T184408Z-runtime-efficiency-raw.jsonl`
- Summary JSON: `docs/evidence/runtime-efficiency/20260611T184408Z-runtime-efficiency-summary.json`

## Harness Command

```text
scripts/benchmark_runtime_efficiency.py --runtimes apple --simple-iterations 5 --db-iterations 5 --backend-iterations 2
```

## Cleanup Scope

The harness cleaned only resources named with the `cca-bench-*` prefix. Cached images and installed Apple runtime setup were left in place.
